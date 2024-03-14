{ config, pkgs, lib, ... }:
let
  wallpaper = ../default/wallpapers/revachol.png;
in
{

  imports =
  [
    ../default/home.nix
  ];

  services.blueman-applet.enable = true;
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
    exec-once = [
        "swaybg -i ${wallpaper} -m fill"
    ];
  };
}
