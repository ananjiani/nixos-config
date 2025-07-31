{
  ...
}:

{

  imports = [
    ../default/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/wallpaper.nix
  ];

  wallpaper = {
    enable = true;
    path = ../default/wallpapers/revachol.png;
    mode = "fill";
  };

  services.mpris-proxy.enable = true;

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "eDP-1,1920x1080@60,0x0,1"
      "DP-4,1920x1080@60,1920x0,1,transform,1"
      "DP-3,1920x1080@60,3000x0,1"
    ];
    workspace = [
      "1, monitor:eDP-1"
      "2, monitor:DP-4"
      "3, monitor:DP-3"
    ];
    # Wallpaper is now handled by the wallpaper module
  };
}
