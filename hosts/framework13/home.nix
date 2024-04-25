{ config, pkgs, lib, ... }:
let wallpaper = ../default/wallpapers/revachol.png;
in {

  imports = [ ../default/home.nix ../../modules/home/work.nix ];

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [ signal-desktop ];
  wayland.windowManager.hyprland.settings = {
    monitor = [
      "eDP-1, 2256x1504@60, 0x0,1"
      "DP-10,1920x1080@60, 2256x0,1,transform,1"
      "DP-9,1920x1080x60, 3336x0,1"
    ];
    workspace = [ "1, monitor:eDP-1" "2, monitor:DP-10" "3, monitor:DP-9" ];
    exec-once = [ "swaybg -i ${wallpaper} -m fill" ];
  };
}
