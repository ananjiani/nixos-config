{
  pkgs,
  ...
}:

{
  imports = [
    ../default/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/wallpaper.nix
    ../../modules/home/work.nix
  ];

  wallpaper = {
    enable = true;
    path = ../default/wallpapers/revachol.png;
    mode = "fill";
  };

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [ signal-desktop ];
  wayland.windowManager.hyprland.settings = {
    monitor = [
      "eDP-1,2256x1504@60,0x0,1.175"
      ",preferred,auto,1"
    ];
    # Wallpaper is now handled by the wallpaper module
  };
}
