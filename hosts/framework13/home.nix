{ config, pkgs, lib, ... }:
let wallpaper = ../default/wallpapers/revachol.png;
in {

  imports = [ ../default/home.nix ../../modules/home/work.nix ];

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [ signal-desktop ];
  wayland.windowManager.hyprland.settings = {
    exec-once = [ "swaybg -i ${wallpaper} -m fill" ];
  };
}
