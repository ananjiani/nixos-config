# Universal foundation for all NixOS systems
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    wget
    zip
    unzip
    killall
    git
    vim
    openssl
    tree
  ];

  programs = {
    fish.enable = true;
    nix-ld.enable = true;
  };

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
        "https://nix-community.cachix.org"
        "https://hyprland.cachix.org"
        "https://claude-code.cachix.org"
        "https://comfyui.cachix.org"
        "https://cache.nixos-cuda.org"
        # "https://attic.dimensiondoor.xyz/middle-earth" # Attic via Traefik (disabled until K8s routing ready)
        "http://theoden.lan:8080/middle-earth" # Attic direct
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "middle-earth:QJM6g097RUDyZA0OG00fXc7JxFMOXN3J5ZBX8j+QfFI="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Chicago";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  networking.firewall = {
    enable = true;
    allowPing = true;
  };

  users.users.ammar = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "dialout" # Serial port access (Zigbee dongles, etc.)
    ];
    shell = pkgs.fish;
  };
}
