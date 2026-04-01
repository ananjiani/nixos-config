# OpenBao - Secrets management server (Vault-compatible)
#
# Deploys OpenBao with Raft integrated storage and optional AWS KMS auto-unseal.
# Designed for a single-node VPS deployment accessed over Tailscale.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.openbao;
in
{
  options.modules.openbao = {
    enable = lib.mkEnableOption "OpenBao secrets manager";

    apiAddr = lib.mkOption {
      type = lib.types.str;
      description = "Public API address for client redirects (e.g., http://erebor.ts:8200)";
      example = "http://erebor.ts:8200";
    };

    clusterAddr = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8201";
      description = "Cluster address for Raft peering (single-node: localhost is fine)";
    };

    enableUI = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the OpenBao web UI";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:8200";
      description = "Address and port for the TCP listener";
    };

    storagePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openbao";
      description = "Path for Raft integrated storage data";
    };

    awsKmsKeyId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "AWS KMS key ID for auto-unseal. Set to null to disable auto-unseal (manual Shamir).";
      example = "arn:aws:kms:eu-central-1:123456789:key/abcd-1234";
    };

    awsKmsRegion = lib.mkOption {
      type = lib.types.str;
      default = "eu-central-1";
      description = "AWS region for KMS auto-unseal";
    };

    awsCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing AWS credentials for KMS auto-unseal (AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openbao = {
      enable = true;
      settings = {
        ui = cfg.enableUI;
        api_addr = cfg.apiAddr;
        cluster_addr = cfg.clusterAddr;

        listener.tcp = {
          type = "tcp";
          address = cfg.listenAddress;
          tls_disable = true; # TLS terminated by Tailscale (WireGuard encryption in transit)
        };

        storage.raft = {
          path = cfg.storagePath;
          node_id = config.networking.hostName;
        };
      }
      // lib.optionalAttrs (cfg.awsKmsKeyId != null) {
        seal.awskms = {
          region = cfg.awsKmsRegion;
          kms_key_id = cfg.awsKmsKeyId;
        };
      };
    };

    # Firewall: allow OpenBao API and cluster ports
    networking.firewall.allowedTCPPorts = [
      8200 # API
      8201 # Cluster (Raft peering)
    ];

    systemd = {
      # Inject AWS credentials for KMS auto-unseal
      services.openbao = lib.mkIf (cfg.awsCredentialsFile != null) {
        serviceConfig.EnvironmentFile = cfg.awsCredentialsFile;
      };

      # Storage directory managed by systemd StateDirectory (DynamicUser)

      # Daily Raft snapshot backup
      timers.openbao-backup = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
      services.openbao-backup = {
        description = "OpenBao Raft snapshot backup";
        after = [ "openbao.service" ];
        requires = [ "openbao.service" ];
        path = [ pkgs.openbao ];
        script = ''
          BACKUP_DIR="/var/backup/openbao"
          mkdir -p "$BACKUP_DIR"
          bao operator raft snapshot save "$BACKUP_DIR/openbao-$(date +%Y%m%d-%H%M%S).snap"
          # Retain last 30 days
          find "$BACKUP_DIR" -name "*.snap" -mtime +30 -delete
        '';
        environment = {
          BAO_ADDR = "http://127.0.0.1:8200";
        };
        serviceConfig = {
          Type = "oneshot";
          # Backup token is stored on disk after initial setup
          EnvironmentFile = "-/var/lib/openbao/backup-env";
        };
      };
    };
  };
}
