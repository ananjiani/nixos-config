{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    webcord
    r2modman
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    wine-wayland
    protontricks
  ];

  programs = { mangohud.enable = true; };
}
