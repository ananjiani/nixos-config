{
  pkgs,
  pkgs-stable,
  ...
}:

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
    wlr.enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
      hyprland = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
    };
  };

  programs = {
    dconf.enable = true;
    hyprland.enable = true;
    hyprland.package = pkgs.hyprland;
    xwayland.enable = true;
  };

  nix.settings = {
    trusted-substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  # xremap home manager
  hardware.uinput.enable = true;
  users.groups.uinput.members = [ "ammar" ];
  users.groups.input.members = [ "ammar" ];

  # Enable touchpad support (enabled default in most desktopManager).

  environment.systemPackages = with pkgs-stable; [
    libreoffice
    imagemagick
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
