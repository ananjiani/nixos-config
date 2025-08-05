# Homeserver configuration
{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../default/configuration.nix
    ../../modules/nixos/services/forgejo.nix
    ../../modules/nixos/services/media.nix
    ../../modules/nixos/services/homeassistant.nix
    ../../modules/nixos/services/reverse-proxy.nix
    ../../modules/nixos/services/vpn-torrents.nix
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
      # Example: Make Mullvad account available for VPN service
      "mullvad/account" = { };
      "mullvad/wireguard_private_key" = { };
    };
  };
}
