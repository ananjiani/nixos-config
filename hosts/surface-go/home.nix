{ config, pkgs, lib, ... }:

let
  wallpaper = ../default/wallpapers/revachol.jpg;
in
{

  imports =
  [ 
    ../default/home.nix
  ];

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  wayland.windowManager.hyprland.settings = {
    monitor = [",highrr,auto,1"];
      exec-once = [
        "swaybg -i ${wallpaper} -m fit"
      ];
  };

}
