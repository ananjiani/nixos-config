# Pippin - Openclaw AI Assistant (Proxmox VM on the-shire)
#
# Dedicated isolated VM for openclaw to safely execute arbitrary commands.
# Uses nix-openclaw Home Manager module for declarative configuration.
{
  inputs,
  pkgs-stable,
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/attic-watch-store.nix
  ];

  # nix-openclaw overlay — provides pkgs.openclaw-gateway, pkgs.openclaw, etc.
  # Template fix is applied per-instance in home.nix (see instances.default.package).
  nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

  networking = {
    hostName = "pippin";
    useDHCP = true;
    nameservers = [
      "192.168.1.53" # AdGuard VIP with internal DNS rewrites
      "9.9.9.9" # Quad9 fallback
    ];
    # Allow openclaw web UI access
    firewall.allowedTCPPorts = [ 18789 ];
  };

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_authkey = { };
      telegram_bot_token = {
        owner = "ammar";
      };
      bifrost_api_key = {
        owner = "ammar";
      };
      tavily_api_key = {
        owner = "ammar";
      };
      elevenlabs_api_key = {
        owner = "ammar";
      };
    };
  };

  modules = {
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      acceptDns = false;
      acceptRoutes = false;
      useExitNode = null; # On LAN, no exit node needed
    };

    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };

  # Enable user lingering so ammar's systemd user services start at boot
  users.users.ammar.linger = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
    sharedModules = [
      inputs.nix-openclaw.homeManagerModules.openclaw
    ];
  };

  # Runtime tools for openclaw shell access
  environment.systemPackages = with pkgs; [
    git
    openssh
    curl
    jq
    # Git platforms
    gh
    codeberg-cli
    # Search/files
    ripgrep
    fd
    tree
    bat
    # Data processing
    yq
    python3
    # Network
    wget
    httpie
    # Archives
    unzip
    zip
    gnutar
    # Browser
    chromium
  ];

  # Prometheus node exporter for VM-level monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };

  services = {
    qemuGuest.enable = true;
    attic-watch-store.enable = true;
  };

  boot = {
    loader.grub.enable = true;
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "virtio_net"
      "sd_mod"
    ];
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
