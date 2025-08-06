# Homeserver configuration
{
  pkgs,
  lib,
  ...
}:

let
  # Load secrets from unencrypted YAML file
  secretsYaml = builtins.readFile ../../homeserver-secrets.yaml;
  secrets = lib.importJSON (
    pkgs.runCommand "secrets-json" { } ''
      ${pkgs.yq}/bin/yq -o json < ${builtins.toFile "secrets.yaml" secretsYaml} > $out
    ''
  );
in
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

  # Service configurations using secrets from YAML
  services.homeserver-proxy = {
    enable = true;
    baseDomain = secrets.domains.base_domain;
    acmeEmail = secrets.acme.email;
  };

  services.homeserver-forgejo = {
    enable = true;
    domain = secrets.domains.forgejo;
  };

  services.homeserver-media = {
    enable = true;
    domains = {
      jellyfin = secrets.domains.jellyfin;
      radarr = secrets.domains.radarr;
      sonarr = secrets.domains.sonarr;
      prowlarr = secrets.domains.prowlarr;
    };
  };

  services.homeserver-vpn-torrents = {
    enable = true;
    mullvadPrivateKey = secrets.mullvad.wireguard_private_key;
    mullvadAddress = secrets.mullvad.wireguard_address;
    mullvadPublicKey = secrets.mullvad.server_public_key;
    mullvadEndpoint = secrets.mullvad.server_endpoint;
    # qBittorrent will be accessible at http://homeserver:8118
  };

  services.homeserver-home-assistant = {
    enable = true;
    domain = secrets.domains.homeassistant;
    # Voice assistant, ESPHome, Matter, and Signal CLI are enabled by default
  };
}
