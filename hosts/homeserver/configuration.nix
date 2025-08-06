# Homeserver configuration
{
  pkgs,
  lib,
  ...
}:

let
  # Load secrets from JSON file (converted from YAML)
  secrets = lib.importJSON ./secrets.json;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/services/reverse-proxy.nix
    ../../modules/nixos/services/forgejo.nix
    # Replaced by nixarr:
    # ../../modules/nixos/services/media.nix
    # ../../modules/nixos/services/vpn-torrents.nix
    ../../modules/nixos/services/home-assistant.nix
  ];

  # Set hostname
  networking.hostName = "homeserver";

  # Boot loader configuration (adjust for your system)
  boot.loader.grub = {
    enable = true;
    devices = [ "nodev" ]; # For UEFI systems
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # System state version
  system.stateVersion = "24.05";

  # Enable Docker as fallback for any services that might need it
  virtualisation.docker.enable = true;

  # Services configuration
  services = {
    # Enable SSH for remote management
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Service configurations using secrets from YAML
    homeserver-proxy = {
      enable = true;
      baseDomain = secrets.domains.base_domain;
      acmeEmail = secrets.acme.email;
    };

    homeserver-forgejo = {
      enable = true;
      domain = secrets.domains.forgejo;
    };

    homeserver-home-assistant = {
      enable = true;
      domain = secrets.domains.homeassistant;
      # Voice assistant, ESPHome, Matter, and Signal CLI are enabled by default
    };

    # Nginx reverse proxy for Jellyfin (nixarr doesn't handle this)
    nginx.virtualHosts.${secrets.domains.jellyfin} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:8096";
        proxyWebsockets = true;
      };
    };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    # These will be managed by individual services
    allowedTCPPorts = [ 22 ]; # SSH
  };

  # System packages for server management
  environment.systemPackages = with pkgs; [
    htop
    iotop
    ncdu
    tmux
    git
    vim
  ];

  # Enable automatic updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = false; # Manual reboots for servers
  };

  # TODO: Enable SOPS once testing is complete
  # For now, we'll read from unencrypted file and create fake secret files
  # sops = {
  #   defaultSopsFile = ../../secrets/homeserver.yaml;
  #   age = {
  #     keyFile = "/var/lib/sops-nix/key.txt";
  #     generateKey = false;
  #   };
  #   secrets = { ... };
  # };

  # Nixarr configuration for media services
  nixarr = {
    enable = true;

    # Set media and state directories
    mediaDir = "/mnt/storage2/arr-data/media";
    stateDir = "/data/.state/nixarr"; # nixarr's default state location

    # VPN configuration for torrents
    vpn = {
      enable = true;
      wgConf =
        if builtins.pathExists ./secrets/mullvad.conf then
          ./secrets/mullvad.conf
        else
          builtins.toFile "mullvad.conf" ''
            # Example WireGuard config - replace with actual config
            [Interface]
            PrivateKey = CHANGE_ME
            Address = 10.0.0.1/32
            DNS = 1.1.1.1

            [Peer]
            PublicKey = CHANGE_ME
            AllowedIPs = 0.0.0.0/0, ::/0
            Endpoint = 1.2.3.4:51820
          '';
    };

    # Enable services (matching your current setup)
    jellyfin = {
      enable = true;
      openFirewall = true;
    };

    radarr = {
      enable = true;
      openFirewall = true;
    };

    sonarr = {
      enable = true;
      openFirewall = true;
    };

    prowlarr = {
      enable = true;
      openFirewall = true;
    };

    # Use Transmission instead of qBittorrent
    transmission = {
      enable = true;
      vpn.enable = true;
      openFirewall = true;
      peerPort = 51413;
    };
  };
}
