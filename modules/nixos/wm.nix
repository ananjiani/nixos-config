{ config, pkgs, lib, ... }:

{
  # services.displayManager.sddm.sugarCandyNix = {
  #   enable = true;
  #   settings = {
  #     Background =
  #       lib.cleanSource ../../hosts/default/wallpapers/revachol-horse.jpg;
  #     ScaleImageCropped = false;
  #     ScreenWidth = 5120;
  #     ScreenHeight = 1440;
  #     FormPosition = "center";
  #     FullBlur = true;
  #     ForceHideCompletePassword = true;
  #     HeaderText = "";
  #     DimBackgroundImage = 0.3;
  #   };
  # };

  # environment.sessionVariables = {
  #   NIXOS_OZONE_WL = "1";
  # };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  programs = {
    dconf.enable = true;
    hyprland.enable = true;
    xwayland.enable = true;
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys =
      [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  # xremap home manager
  hardware.uinput.enable = true;
  users.groups.uinput.members = [ "ammar" ];
  users.groups.input.members = [ "ammar" ];

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  environment.systemPackages = with pkgs; [
    openconnect
    libreoffice
    imagemagick
    firefox
    remmina
    wl-clipboard
    pavucontrol
    light
    libnotify
    copyq
    hyprpicker
    wlogout
    swaybg
    grim
    slurp
    wl-clipboard
    swappy
    nwg-displays
    wlr-randr
    polkit_gnome
  ];
}
