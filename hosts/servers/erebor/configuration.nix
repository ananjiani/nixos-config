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
    vault-agent.address = "http://127.0.0.1:8200";
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
  systemd.services.vault-agent-default = {
    after = [ "openbao.service" ];
    wants = [ "openbao.service" ];
  };
  systemd.services.attic-watch-store = {
    after = [ "vault-agent-default.service" ];
    wants = [ "vault-agent-default.service" ];
  };

  # Use Attic binary cache via Cloudflare Tunnel (erebor can't reach theoden.lan)
  nix.settings.extra-substituters = [ "https://attic.dimensiondoor.xyz/middle-earth" ];

  # Boot: GRUB for BIOS boot (Hetzner CX-series uses SeaBIOS)
  # Device is set automatically by disko via the EF02 partition
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
