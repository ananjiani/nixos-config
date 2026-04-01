# Erebor - Hetzner VPS (OpenBao secrets manager)
#
# External VPS hosting OpenBao for centralized secrets management.
# Accessed exclusively over Tailscale (no public API exposure).
{
  inputs,
  pkgs-stable,
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
  ];

  modules = {
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      # authKeyFile = config.sops.secrets.tailscale_authkey.path;  # TODO: re-enable after placing age key
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
      # AWS KMS auto-unseal — set after creating KMS key
      # awsKmsKeyId = "arn:aws:kms:eu-central-1:ACCOUNT:key/KEY-ID";
      # awsCredentialsFile = config.sops.secrets.aws_kms_credentials.path;
    };
  };

  # SOPS secrets — minimal, only for bootstrapping
  # Once vault-agent is set up, this can be removed
  # TODO: re-enable after placing age key on server (/var/lib/sops-nix/key.txt)
  # sops = {
  #   defaultSopsFile = ../../../secrets/secrets.yaml;
  #   age.keyFile = "/var/lib/sops-nix/key.txt";
  #   secrets.tailscale_authkey = { };
  # };

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
