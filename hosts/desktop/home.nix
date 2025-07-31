{
  lib,
  ...
}:

{
  imports = [
    ../default/home.nix
    ../../modules/home/gaming.nix
    ../../modules/home/config/wallpaper.nix
  ];

  wallpaper = {
    enable = true;
    path = ../default/wallpapers/revachol.jpg;
    mode = lib.mkForce "fit";
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "DP-2,5120x1440@240,0x1440,1,vrr,2"
      "DP-1,3840x2160@60,2560x0,1.5"
      "HDMI-A-1,2560x1440@60,0x0,1"
    ];
    exec-once = [
      "corectrl"
      "steam -silent -cef-disable-gpu"
    ];
  };
}
