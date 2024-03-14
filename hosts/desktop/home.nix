{ config, pkgs, lib, ... }:

let
  wallpaper = ./wallpapers/revachol.jpg;
in
{
  imports =
  [ 
    ../../home/emacs/emacs.nix
    ../../home/home-gaming.nix
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


  wayland.windowManager.hyprland.settings = {
      monitor = [
      "DP-2,5120x1440@240,0x1440,1,vrr,2"
      "DP-1,3840x2160@60,2560x360,2"
      "HDMI-A-1,2560x1440@60,0x0,1"
      ];
      general.layout = "dwindle";
      exec-once = [
        "corectrl"
        "steam -silent -cef-disable-gpu"
        "swaybg -i ${wallpaper} -m fit"
      ];
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
