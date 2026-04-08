# Erebor - Hetzner VPS (OpenBao secrets manager)
#
# External VPS hosting OpenBao for centralized secrets management.
# Accessed exclusively over Tailscale (no public API exposure).
{
  inputs,
  pkgs-stable,
  config,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/openbao.nix
    ../../../modules/nixos/server/vault-mcp-server.nix
    ../../../modules/nixos/vault-agent.nix
  ];

  modules = {
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      acceptDns = false;
      acceptRoutes = false;
      useExitNode = null; # VPS has its own internet access
    };

    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
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

    # Vault agent — fetches secrets from local OpenBao
    vault-agent = {
      enable = true;
      address = "http://127.0.0.1:8200"; # localhost (OpenBao runs on this machine)
      roleIdFile = config.sops.secrets.vault_role_id_server.path;
      secretIdFile = config.sops.secrets.vault_secret_id_server.path;
      # Secrets will be declared here as services are added (ntfy, Gatus, Headscale, etc.)
      secrets = { };
    };
  };

  # SOPS bootstraps vault-agent credentials + Tailscale auth
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      tailscale_authkey = { };
      vault_role_id_server = { };
      vault_secret_id_server = { };
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

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Prometheus node exporter for monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };

  # vault-agent must wait for local OpenBao to be ready (unique to erebor)
  systemd.services.vault-agent-default = {
    after = [ "openbao.service" ];
    wants = [ "openbao.service" ];
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

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
