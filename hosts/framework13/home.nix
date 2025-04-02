{ config, pkgs, lib, ... }:
let wallpaper = ../default/wallpapers/revachol.png;
in {

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [ signal-desktop ];
  wayland.windowManager.hyprland.settings = {
    monitor = [ "eDP-1,2256x1504@60,0x0,1.175" ",preferred,auto,1" ];
    exec-once = [ "swaybg -i ${wallpaper} -m fill" ];
  };
}
