{ config, pkgs, lib, ... }: {
  home.packages = with pkgs; [
    inkscape
    vlc
    kdenlive
    xfce.thunar
    xfce.thunar-archive-plugin
    xfce.thunar-media-tags-plugin
  ];
}
