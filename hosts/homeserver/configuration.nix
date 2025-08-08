# Homeserver configuration
{
  config,
  pkgs,
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../modules/nixos/services/forgejo.nix
    # Replaced by nixarr:
    # ../../modules/nixos/services/media.nix
    # ../../modules/nixos/services/vpn-torrents.nix
    ../../modules/nixos/services/home-assistant.nix
  ];

  # Set hostname
  networking.hostName = "homeserver";

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Boot loader configuration (adjust for your system)
  boot.loader.grub = {
    enable = true;
    devices = [ "nodev" ]; # For UEFI systems
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # System state version
  system.stateVersion = "24.05";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Nix configuration for trusted keys and caches
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "ammar"
      ];
      substituters = [
        "https://hyprland.cachix.org"
        "https://claude-code.cachix.org"
      ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

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

    homeserver-forgejo = {
      enable = true;
      domain = "localhost"; # Local access only
    };

    homeserver-home-assistant = {
      enable = true;
      domain = "homeassistant.local"; # Local access only
      # Voice assistant, ESPHome, Matter, and Signal CLI are enabled by default
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

  # User configuration for VM testing
  users.users.root.initialPassword = "test";
  users.users.ammar = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    initialPassword = "test";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoo8KQiLBJ6WrWmG0/6O8lww/v6ggPaLfv70/ksMZbD ammar.nanjiani@gmail.com"
    ];
  };

  # Enable automatic updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = false; # Manual reboots for servers
  };

  # SOPS configuration for secrets management
  sops = {
    defaultSopsFile = ../../secrets/homeserver.yaml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };
    secrets = {
      # Optional: Forgejo admin password (can set via web UI instead)
      "forgejo/admin_password" = {
        owner = "forgejo";
        restartUnits = [ "forgejo.service" ];
      };

      # Mullvad VPN configuration (required if using VPN)
      "mullvad/wireguard_private_key" = { };
      "mullvad/wireguard_address" = { };
      "mullvad/server_public_key" = { };
      "mullvad/server_endpoint" = { };

      # Optional: Home Assistant MQTT password (anonymous MQTT enabled by default)
      # "homeassistant/mqtt_password" = {
      #   owner = "homeassistant";
      #   group = "homeassistant";
      # };
    };
  };

  # Create WireGuard config from SOPS secrets if available
  systemd.services.nixarr-wireguard-config = {
    description = "Generate WireGuard config for nixarr";
    before = [ "nixarr.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/nixarr
      cat > /var/lib/nixarr/wg0.conf <<EOF
      [Interface]
      PrivateKey = $(cat ${config.sops.secrets."mullvad/wireguard_private_key".path})
      Address = $(cat ${config.sops.secrets."mullvad/wireguard_address".path})
      DNS = 1.1.1.1

      [Peer]
      PublicKey = $(cat ${config.sops.secrets."mullvad/server_public_key".path})
      AllowedIPs = 0.0.0.0/0, ::/0
      Endpoint = $(cat ${config.sops.secrets."mullvad/server_endpoint".path})
      EOF
      chmod 600 /var/lib/nixarr/wg0.conf
    '';
  };

  # Nixarr configuration for media services
  nixarr = {
    enable = true;

    # Set media and state directories
    mediaDir = "/mnt/storage2/arr-data/media";
    stateDir = "/data/.state/nixarr"; # nixarr's default state location

    # VPN configuration for torrents
    vpn = {
      enable = true;
      wgConf = "/var/lib/nixarr/wg0.conf";
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

    transmission = {
      enable = true;
      vpn.enable = true;
      openFirewall = true;
      peerPort = 51413;
    };
  };
}
