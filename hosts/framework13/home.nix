{
  pkgs,
  ...
}:

{
  imports = [
    ../profiles/workstation/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/wallpaper.nix
    ../../modules/home/config/sops.nix
    ../../modules/home/work.nix
  ];

  wallpaper = {
    enable = true;
    mode = "fill";
  };

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [
    signal-desktop
    moonlight-qt
  ];
  wayland.windowManager.hyprland.settings = {
    monitor = [
      "eDP-1,2256x1504@60,0x0,1.175"
      ",preferred,auto,1"
    ];
    # Wallpaper is now handled by the wallpaper module
  };
}
