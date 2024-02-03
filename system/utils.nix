#Stuff that will be universally useful.

{ config, pkgs, lib, ...}:

{
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
    sops
  ];

  # xremap home manager
  hardware.uinput.enable = true;
  users.groups.uinput.members = ["ammar"];
  users.groups.input.members = ["ammar"];

  programs.fish.enable = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
