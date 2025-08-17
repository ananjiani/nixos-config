# Forgejo git forge with runners
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.homeserver-forgejo;
in
{
  options.services.homeserver-forgejo = {
    enable = lib.mkEnableOption "Forgejo git forge";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Domain name for Forgejo";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/storage1/forgejo";
      description = "Data directory for Forgejo";
    };

    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "SSH port for git operations";
    };
  };

  config = lib.mkIf cfg.enable {
    # Services configuration
    services = {
      # Forgejo service
      forgejo = {
        enable = true;
        stateDir = cfg.dataDir;

        settings = {
          server = {
            DOMAIN = cfg.domain;
            ROOT_URL = "http://${cfg.domain}:3000";
            SSH_PORT = cfg.sshPort;
          };

          service = {
            DISABLE_REGISTRATION = true;
          };

          # Enable actions (CI/CD)
          actions = {
            ENABLED = true;
          };
        };

        # Database
        database = {
          type = "sqlite3";
        };
      };

      # Forgejo runner with SOPS integration
      gitea-actions-runner = lib.mkIf (config.sops.secrets ? "forgejo/runner_token") {
        package = pkgs.forgejo-actions-runner;
        instances.default = {
          enable = true;
          name = "homeserver-runner";
          url = "http://localhost:3000";
          tokenFile = config.sops.secrets."forgejo/runner_token".path;
          labels = [
            "nixos:docker://nixos/nix:latest"
            "ubuntu-latest:docker://ubuntu:latest"
          ];
        };
      };

      # No nginx - direct access only
    };

    # System services for admin password setup
    systemd.services.forgejo-admin-setup = lib.mkIf (config.sops.secrets ? "forgejo/admin_password") {
      description = "Forgejo admin password setup";
      after = [ "forgejo.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "forgejo";
        StateDirectory = "forgejo-admin-setup";
      };
      script = ''
        if [ ! -f /var/lib/forgejo-admin-setup/admin-created ]; then
          ${pkgs.forgejo}/bin/forgejo admin user create \
            --username admin \
            --password "$(cat ${config.sops.secrets."forgejo/admin_password".path})" \
            --email "admin@${cfg.domain}" \
            --admin \
            --config ${config.services.forgejo.customDir}/conf/app.ini || true
          touch /var/lib/forgejo-admin-setup/admin-created
        fi
      '';
    };
  };
}
