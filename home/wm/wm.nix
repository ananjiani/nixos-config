{ config, pkgs, lib, nix-colors, ... }:

let
  nix-colors-lib = nix-colors.lib.control {inherit pkgs; };
  
in
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

    alacritty = {
      enable = true;
      settings = {
            window = {
            opacity = 0.8;
            blur = true;
          };
        colors = with config.colorScheme.colors; {
          bright = {
            black = "0x${base00}";
            blue = "0x${base0D}";
            cyan = "0x${base0C}";
            green = "0x${base0B}";
            magenta = "0x${base0E}";
            red = "0x${base08}";
            white = "0x${base06}";
            yellow = "0x${base09}";
          };
          cursor = {
            cursor = "0x${base06}";
            text = "0x${base06}";
          };
          normal = {
            black = "0x${base00}";
            blue = "0x${base0D}";
            cyan = "0x${base0C}";
            green = "0x${base0B}";
            magenta = "0x${base0E}";
            red = "0x${base08}";
            white = "0x${base06}";
            yellow = "0x${base0A}";
          };
          primary = {
            background = "0x${base00}";
            foreground = "0x${base06}";
          };
        }; 
      };
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];
      general = {
        "col.active_border" = with config.colorScheme.colors; "rgba(${base09}ee) rgba(${base0A}ee) 45deg";
      };
    };
    extraConfig = builtins.readFile ../../home/wm/hyprland.conf;
  };
}

