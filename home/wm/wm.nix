{ config, pkgs, lib, nix-colors, ... }:


{
  home.packages = with pkgs; [
    swaynotificationcenter
    waybar
  ];

  imports = [
    nix-colors.homeManagerModules.default
  ];

  colorScheme = nix-colors.colorSchemes.gruvbox-material-dark-soft;
  #   colorScheme = nix-colors-lib.colorSchemeFromPicture {
  #     path = wallpaper;
  #     kind = "dark";
  #   };

  gtk = {
    enable = true;
    theme= {
      name = "gruvbox-dark";
      package = pkgs.gruvbox-dark-gtk;
    };
    iconTheme.package = pkgs.gruvbox-dark-icons-gtk;
    iconTheme.name = "Gruvbox-Dark";
  };

  home.file = {
    ".config/waybar/config.jsonc".source = ../../home/wm/waybar/config.jsonc;
    ".config/waybar/style.css".source = ../../home/wm/waybar/style.css;
    ".config/swaync/config.json".source = ../../home/wm/swaync/config.json;
    ".config/swaync/style.css".source = ../../home/wm/swaync/style.css;
  };

  programs = {
    fuzzel = {
      enable = true;
      settings = {
        colors = with config.colorScheme.colors;{
          background = "${base00}ff";
          text = "${base05}ff";
          match = "${base08}ff";
          selection = "${base01}ff";
          selection-text = "${base05}ff";
          selection-match = "${base08}ff";
          border = "${base09}ff";
        };
      };
    };

    
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      exec = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];
      general = {
        "col.active_border" = with config.colorScheme.colors; "rgba(${base09}ee) rgba(${base0A}ee) 45deg";
      };
      "$mainMod" = "SUPER";
      bind = [
        "$mainMod, Q, exec, foot"
      ];
    };
    extraConfig = builtins.readFile ../../home/wm/hyprland.conf;
  };
}

