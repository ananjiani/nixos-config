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

  # xremap home manager
  hardware.uinput.enable = true;
  users.groups.uinput.members = [ "ammar" ];
  users.groups.input.members = [ "ammar" ];

  # Enable touchpad support (enabled default in most desktopManager).

  environment.systemPackages = with pkgs; [
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

  services = {
    libinput.enable = true;
    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };

    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      xkb.layout = "us";
    };

    # Configure pipewire
    pipewire = {
      enable = true;
      wireplumber.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # jack.enable = true;
    };

    # Enable CUPS to print documents.
    printing.enable = true;

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    upower.enable = true;

    flatpak.enable = true;

    dbus.enable = true;

    gvfs.enable = true;
  };
}
