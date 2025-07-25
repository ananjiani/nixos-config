{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.wallpaper;
in
{
  options.wallpaper = {
    enable = mkEnableOption "wallpaper configuration";
    
    path = mkOption {
      type = types.path;
      default = ../../hosts/default/wallpapers/revachol.jpg;
      description = "Path to the wallpaper image";
    };
    
    mode = mkOption {
      type = types.enum [ "fill" "fit" "center" "stretch" "tile" ];
      default = "fill";
      description = "Wallpaper display mode";
    };
  };

  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.settings.exec-once = [
      "swaybg -i ${cfg.path} -m ${cfg.mode}"
    ];
  };
}