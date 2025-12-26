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
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
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
