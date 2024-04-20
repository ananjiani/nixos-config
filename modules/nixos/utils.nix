# Stuff that will be universally useful.

{ config, pkgs, lib, ... }:

{

  imports = [ ./fonts.nix ];

  environment.systemPackages = with pkgs; [
    wget
    zip
    unzip
    killall
    neofetch
    libreoffice
    imagemagick
    firefox
    remmina
    openconnect
    libsForQt5.qt5.qtgraphicaleffects
  ];

 boot.kernelPackages = pkgs.linuxPackages_6_1;

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys =
      [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  # xremap home manager
  hardware.uinput.enable = true;
  users.groups.uinput.members = [ "ammar" ];
  users.groups.input.members = [ "ammar" ];

  programs.fish.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "ammar" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
