# Homeserver configuration
{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/services/reverse-proxy.nix
    ../../modules/nixos/services/forgejo.nix
    ../../modules/nixos/services/media.nix
    ../../modules/nixos/services/vpn-torrents.nix
    ../../modules/nixos/services/home-assistant.nix
  ];

  # Set hostname
  networking.hostName = "homeserver";

  # Enable Docker as fallback for any services that might need it
  virtualisation.docker.enable = true;

  # Enable SSH for remote management
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
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

  # SOPS configuration for system-level secrets
  sops = {
    defaultSopsFile = ../../secrets/homeserver.yaml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false; # Don't auto-generate, we'll create it manually
    };
    # Define secrets that will be available system-wide
    secrets = {
      # VPN secrets
      "mullvad/account" = { };
      "mullvad/wireguard_private_key" = { };

      # Domain configuration
      "domains/base_domain" = { };
      "domains/forgejo" = { };
      "domains/jellyfin" = { };
      "domains/homeassistant" = { };
      "domains/radarr" = { };
      "domains/sonarr" = { };
      "domains/prowlarr" = { };

      # ACME email
      "acme/email" = { };
    };
  };

  # Service configurations
  # TODO: These will use SOPS secrets once we set up proper templating
  services.homeserver-proxy = {
    enable = true;
    baseDomain = "example.com"; # Will be replaced from SOPS
    acmeEmail = "admin@example.com"; # Will be replaced from SOPS
  };

  services.homeserver-forgejo = {
    enable = true;
    domain = "git.example.com"; # Will be replaced from SOPS
  };

  services.homeserver-media = {
    enable = true;
    domains = {
      jellyfin = "media.example.com"; # Will be replaced from SOPS
      radarr = "radarr.example.com"; # Will be replaced from SOPS
      sonarr = "sonarr.example.com"; # Will be replaced from SOPS
      prowlarr = "prowlarr.example.com"; # Will be replaced from SOPS
    };
  };

  services.homeserver-vpn-torrents = {
    enable = true;
    # qBittorrent will be accessible at http://homeserver:8118
  };

  services.homeserver-home-assistant = {
    enable = true;
    domain = "home.example.com"; # Will be replaced from SOPS
    # Voice assistant, ESPHome, Matter, and Signal CLI are enabled by default
  };
}
