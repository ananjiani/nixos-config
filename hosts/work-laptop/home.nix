{ config, pkgs, lib, ... }:
let
  wallpaper = ./wallpapers/revachol.png;
in
{

  imports =
  [ 
    ../../home/emacs/emacs.nix
    ../../home/wm/wm.nix
    ../../home/utils.nix
    ../../home/defaults.nix
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ammar";
  home.homeDirectory = "/home/ammar";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  # home.packages = with pkgs; [
  # ];

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
    general.layout = "dwindle";
    exec-once = [
        "swaybg -i ${wallpaper} -m fill"
    ];
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
