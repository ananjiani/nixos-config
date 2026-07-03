# Erebor - Hetzner VPS (OpenBao secrets manager)
#
# External VPS hosting OpenBao for centralized secrets management.
# Accessed exclusively over Tailscale (no public API exposure).
{
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
    ../../_profiles/server/configuration.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/server/openbao.nix
    ../../../modules/nixos/server/vault-mcp-server.nix
    ../../../modules/nixos/caddy.nix
    ../../../modules/nixos/headscale.nix
  ];

  modules = {
    proxmoxGuest = false; # Hetzner VPS, not a Proxmox VM

    # Tailscale without exit node or subnet routes (not on homelab LAN)
    tailscale = {
      enable = true;
      exitNode = false;
      subnetRoutes = [ ];
    };

    openbao = {
      enable = true;
      apiAddr = "http://erebor.ts:8200";
      enableUI = true;
      # AWS KMS auto-unseal
      awsKmsKeyId = "arn:aws:kms:eu-central-1:017562255035:key/76bd5390-cdbf-462d-bd9b-c45069d9e54f";
      awsKmsRegion = "eu-central-1";
      awsCredentialsFile = "/var/lib/openbao/aws-kms-env";
    };

    vault-mcp-server = {
      enable = true;
      tokenFile = "/var/lib/openbao/mcp-token";
    };

    # Override vault-agent to use local OpenBao (base.nix defaults to erebor's Tailscale IP)
    vault-agent = {
      address = "http://127.0.0.1:8200";
      secrets = {
        cloudflare_api_token = {
          path = "secret/k8s/cert-manager";
          field = "api-token"; # ignored because template is set
          template = ''CF_API_TOKEN={{ with secret "secret/data/k8s/cert-manager" }}{{ index .Data.data "api-token" }}{{ end }}'';
          owner = "caddy";
          group = "caddy";
          mode = "0400";
        };
        # Offsite backups (issue #41): same S3-style pattern as theoden
        b2_env = {
          path = "secret/nixos/backblaze";
          template = ''
            AWS_ACCESS_KEY_ID={{ with secret "secret/data/nixos/backblaze" }}{{ .Data.data.key_id }}{{ end }}
            AWS_SECRET_ACCESS_KEY={{ with secret "secret/data/nixos/backblaze" }}{{ .Data.data.application_key }}{{ end }}
          '';
        };
        restic_pw = {
          path = "secret/nixos/restic";
          field = "password";
        };
      };
    };

    caddy = {
      enable = true;
      email = "ammar@dimensiondoor.xyz";
      cloudflareEnvFile = "/run/secrets/cloudflare_api_token";
      virtualHosts."ts.dimensiondoor.xyz" = {
        upstream = "127.0.0.1:8080";
        useCloudflareDns = true;
      };
    };

    headscale = {
      enable = true;
      domain = "ts.dimensiondoor.xyz";
      baseDomain = "tail.dimensiondoor.xyz";
      aclPolicyFile = ../../../modules/nixos/headscale-acl.json;
    };
  };

  # Offsite backup of OpenBao Raft snapshots (issue #41). The openbao-backup
  # timer writes daily snapshots to /var/backup/openbao at midnight; this
  # ships them to B2 an hour later. Raft snapshots do NOT include unseal
  # material — recovery also needs the AWS KMS key (in AWS) and the restic
  # password + B2 key (password manager).
  services.restic.backups.openbao-offsite = {
    repository = "s3:s3.us-east-005.backblazeb2.com/ammars-homelab-offsite/erebor/openbao";
    paths = [ "/var/backup/openbao" ];
    environmentFile = "/run/secrets/b2_env";
    passwordFile = "/run/secrets/restic_pw";
    initialize = true;
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
      "--keep-yearly 2"
    ];
    timerConfig = {
      OnCalendar = "01:00";
      Persistent = true;
    };
  };

  networking = {
    hostName = "erebor";
    useDHCP = true;
    nameservers = [
      "1.1.1.1" # Cloudflare (public VPS, not on homelab LAN)
      "9.9.9.9" # Quad9 fallback
    ];
  };

  # Systemd ordering unique to erebor: OpenBao is local, so vault-agent
  # must wait for it, and attic-watch-store must wait for vault-agent
  systemd.services = {
    vault-agent-default = {
      after = [ "openbao.service" ];
      wants = [ "openbao.service" ];
    };
    attic-watch-store = {
      after = [ "vault-agent-default.service" ];
      wants = [ "vault-agent-default.service" ];
    };
    restic-backups-openbao-offsite.after = [ "vault-agent-default.service" ];
  };

  # Use Attic binary cache via Cloudflare Tunnel (erebor can't reach theoden.lan)
  nix.settings.extra-substituters = [ "https://attic.dimensiondoor.xyz/middle-earth?priority=10" ];

  # Boot: GRUB for BIOS boot (Hetzner CX-series uses SeaBIOS)
  # Device is set automatically by disko via the EF02 partition
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
