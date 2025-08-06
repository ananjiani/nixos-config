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
    # Forgejo service
    services.forgejo = {
      enable = true;
      stateDir = cfg.dataDir;

      settings = {
        server = {
          DOMAIN = cfg.domain;
          ROOT_URL = "https://${cfg.domain}";
          HTTP_PORT = 3000;
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

    # Forgejo runner
    services.gitea-actions-runner = {
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

    # Nginx reverse proxy
    services.nginx.virtualHosts.${cfg.domain} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:3000";
      };
    };

    # Open firewall
    networking.firewall.allowedTCPPorts = [ cfg.sshPort ];

    # SOPS secrets
    sops.secrets = {
      "forgejo/admin_password" = {
        owner = "forgejo";
      };
      "forgejo/runner_token" = {
        owner = "gitea-runner";
      };
    };
  };
}
