# Homeserver configuration
{
  config,
  pkgs,
  lib,
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../modules/nixos/services/reverse-proxy.nix
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

    # Service configurations using SOPS secrets
    homeserver-proxy = {
      enable = true;
      baseDomain = "example.com"; # Use real domain in secrets/homeserver.yaml
      acmeEmail = "admin@example.com"; # Use real email in secrets/homeserver.yaml
    };

    homeserver-forgejo = {
      enable = true;
      domain = "git.example.com"; # Use real domain in secrets/homeserver.yaml
    };

    homeserver-home-assistant = {
      enable = true;
      domain = "homeassistant.local"; # Use real domain in secrets/homeserver.yaml
      # Voice assistant, ESPHome, Matter, and Signal CLI are enabled by default
    };

    # Nginx reverse proxy for Jellyfin (nixarr doesn't handle this)
    nginx.virtualHosts."media.example.com" = {
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
      # Forgejo secrets
      "forgejo/admin_password" = {
        owner = "forgejo";
        restartUnits = [ "forgejo.service" ];
      };
      "forgejo/runner_token" = {
        owner = "root";
      };
      "forgejo/lfs_jwt_secret" = {
        owner = "forgejo";
      };

      # Mullvad VPN configuration
      "mullvad/wireguard_private_key" = { };
      "mullvad/wireguard_address" = { };
      "mullvad/server_public_key" = { };
      "mullvad/server_endpoint" = { };

      # Home Assistant secrets
      "homeassistant/mqtt_password" = {
        owner = "homeassistant";
        group = "homeassistant";
      };
      "homeassistant/signal_api_key" = {
        owner = "homeassistant";
        group = "homeassistant";
      };

      # Arr stack secrets
      "arr_stack/radarr_api_key" = { };
      "arr_stack/sonarr_api_key" = { };
      "arr_stack/prowlarr_api_key" = { };
      "arr_stack/transmission_password" = { };

      # Domain configuration
      "domains/base_domain" = { };
      "domains/forgejo" = { };
      "domains/jellyfin" = { };
      "domains/homeassistant" = { };

      # ACME email
      "acme/email" = { };
    };
  };

  # Create WireGuard config from SOPS secrets if available
  systemd.services.nixarr-wireguard-config =
    lib.mkIf (config.sops ? secrets && config.sops.secrets ? "mullvad/wireguard_private_key")
      {
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
      wgConf =
        if config.sops ? secrets && config.sops.secrets ? "mullvad/wireguard_private_key" then
          "/var/lib/nixarr/wg0.conf"
        else if builtins.pathExists ./secrets/mullvad.conf then
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
