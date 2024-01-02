{ config, pkgs, lib, ...}:

{
  services.xserver.displayManager.sddm.sugarCandyNix = {
    enable = true;
    settings = {
        Background = lib.cleanSource ../profiles/work-laptop/wallpapers/revachol-horse.jpg;
        ScaleImageCropped = false;
        ScreenWidth = 5120;
        ScreenHeight = 1440;
        FormPosition = "center";
        FullBlur = true;
        ForceHideCompletePassword = true;
        HeaderText = "";
        DimBackgroundImage = 0.3;
    };
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  xdg.portal = {
    enable = true;
    config.common.default = "*";
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };

  fonts.packages = with pkgs; [
    nerdfonts
    font-awesome
  ];

  programs = {
    thunar.enable = true;
    file-roller.enable = true;
    dconf.enable = true;
  };
  
  environment.systemPackages = with pkgs; [
    libnotify
    image-roll
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
