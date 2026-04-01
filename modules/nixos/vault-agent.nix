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

  # Build Consul Template snippets for each secret
  secretTemplates = lib.mapAttrsToList (
    name: secret:
    let
      templateContent = ''{{ with secret "${secret.path}" }}{{ .Data.data.${secret.field} }}{{ end }}'';
    in
    {
      contents = templateContent;
      destination = "/run/secrets/${name}";
      perms = secret.mode;
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
              description = "Field name within the secret";
              example = "token";
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

    # Fix ownership after template rendering (vault-agent creates files as root,
    # but services may need them owned by specific users)
    systemd.services.vault-agent-default.serviceConfig.ExecStartPost =
      lib.mkIf (lib.any (s: s.owner != "root" || s.group != "root") (lib.attrValues cfg.secrets))
        (
          let
            ownershipScript = pkgs.writeShellScript "vault-agent-fix-ownership" (
              lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: secret:
                  lib.optionalString (
                    secret.owner != "root" || secret.group != "root"
                  ) "chown ${secret.owner}:${secret.group} /run/secrets/${name} 2>/dev/null || true"
                ) cfg.secrets
              )
            );
          in
          [ "+${ownershipScript}" ]
        );
  };
}
