{ config, pkgs, lib, ... }:
let wallpaper = ../default/wallpapers/revachol.png;
in {

  imports = [ ../default/home.nix ];

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [ signal-desktop ];
  wayland.windowManager.hyprland.settings = {
    monitor = [ ",preferred,auto,1" ];
    exec-once = [ "swaybg -i ${wallpaper} -m fill" ];
  };
}
