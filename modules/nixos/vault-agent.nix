# Vault Agent for OpenBao - Client-side secret fetching
#
# Wraps services.vault-agent to provide a sops-nix-like interface for
# fetching secrets from OpenBao and writing them to /run/secrets/.
# Uses AppRole authentication.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.vault-agent;

  # Build Consul Template snippets for each secret.
  # `user`/`group` are re-applied by Consul Template on every render
  # (including lease-renewal re-renders), which is why we can't rely on
  # a one-shot ExecStartPost chown — that only runs at service start.
  secretTemplates = lib.mapAttrsToList (
    name: secret:
    let
      defaultTemplate = ''{{ with secret "${secret.path}" }}{{ index .Data.data "${secret.field}" }}{{ end }}'';
      templateContent = if secret.template != null then secret.template else defaultTemplate;
    in
    {
      contents = templateContent;
      destination = "/run/secrets/${name}";
      perms = secret.mode;
      user = secret.owner;
      inherit (secret) group;
    }
  ) cfg.secrets;
in
{
  options.modules.vault-agent = {
    enable = lib.mkEnableOption "Vault agent for OpenBao secret retrieval";

    address = lib.mkOption {
      type = lib.types.str;
      default = "http://erebor.ts:8200";
      description = "OpenBao server address (via Tailscale)";
    };

    roleIdFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vault-agent/role-id";
      description = "Path to file containing AppRole role_id";
    };

    secretIdFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vault-agent/secret-id";
      description = "Path to file containing AppRole secret_id";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "OpenBao KV v2 secret path (e.g., secret/nixos/k3s)";
              example = "secret/nixos/k3s";
            };
            field = lib.mkOption {
              type = lib.types.str;
              description = "Field name within the secret (ignored if `template` is set)";
              example = "token";
            };
            template = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Optional Consul Template body. When set, rendered verbatim
                instead of the default single-field template. Useful for
                multi-line output formats like EnvironmentFile.
              '';
              example = ''CF_API_TOKEN={{ with secret "secret/data/k8s/cert-manager" }}{{ .Data.data.api-token }}{{ end }}'';
            };
            owner = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "Owner of the rendered secret file";
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "Group of the rendered secret file";
            };
            mode = lib.mkOption {
              type = lib.types.str;
              default = "0400";
              description = "File permissions for the rendered secret";
            };
          };
        }
      );
      default = { };
      description = "Secrets to fetch from OpenBao. Each key becomes /run/secrets/<key>.";
      example = {
        k3s_token = {
          path = "secret/nixos/k3s";
          field = "token";
        };
        tailscale_authkey = {
          path = "secret/nixos/tailscale";
          field = "authkey";
        };
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.secrets != { }) {
    # Use the vault-agent instances module with OpenBao package
    services.vault-agent.instances.default = {
      enable = true;
      package = pkgs.openbao;
      settings = {
        vault.address = cfg.address;

        auto_auth = [
          {
            method = [
              {
                type = "approle";
                config = {
                  role_id_file_path = cfg.roleIdFile;
                  secret_id_file_path = cfg.secretIdFile;
                  remove_secret_id_file_after_reading = false;
                };
              }
            ];
            sink = [
              {
                type = "file";
                config = {
                  path = "/run/vault-agent/token";
                  mode = 384; # 0600 in decimal
                };
              }
            ];
          }
        ];

        template = secretTemplates;
      };
    };

    # Ensure /run/secrets and /run/vault-agent directories exist
    systemd.tmpfiles.rules = [
      "d /run/secrets 0755 root root -"
      "d /run/vault-agent 0700 root root -"
      "d /var/lib/vault-agent 0700 root root -"
    ];

    # sops-nix's setupSecrets activation clears /run/secrets entries it
    # doesn't own, wiping vault-agent's renders on every deploy. Force a
    # re-render by restarting vault-agent after sops has run.
    system.activationScripts.vault-agent-rehydrate = lib.stringAfter [ "setupSecrets" ] ''
      if ${pkgs.systemd}/bin/systemctl is-active --quiet vault-agent-default.service; then
        ${pkgs.systemd}/bin/systemctl try-restart vault-agent-default.service || true
      fi
    '';

    # Wait for all secrets to be rendered before considering the unit
    # started. vault-agent is Type=simple so systemd would otherwise
    # consider it up before the first template render completes. Any
    # service with After=vault-agent-default.service gets to assume
    # that /run/secrets/<name> exists. Ownership is enforced by
    # Consul Template via the `user`/`group` template options above,
    # which re-apply on every render (including lease renewals).
    systemd.services.vault-agent-default.serviceConfig.ExecStartPost =
      let
        secretNames = lib.attrNames cfg.secrets;
        waitScript = pkgs.writeShellScript "vault-agent-wait-secrets" ''
          for i in $(seq 1 60); do
            all_exist=true
            ${lib.concatMapStringsSep "\n" (name: ''
              [ -f /run/secrets/${name} ] || all_exist=false
            '') secretNames}
            if $all_exist; then
              break
            fi
            sleep 1
          done
          if ! $all_exist; then
            echo "vault-agent: timed out waiting for secrets" >&2
            exit 1
          fi
        '';
      in
      [ "+${waitScript}" ];
  };
}
