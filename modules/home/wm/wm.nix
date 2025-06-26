{
  config,
  pkgs,
  pkgs-stable,
  lib,
  inputs,
  ...
}:
{
  home.packages = with pkgs; [ swaynotificationcenter ];

  imports = [ inputs.nix-colors.homeManagerModules.default ];

  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-material-dark-soft;
  #   colorScheme = nix-colors-lib.colorSchemeFromPicture {
  #     path = wallpaper;
  #     kind = "dark";
  #   };

  gtk = {
    enable = true;
    theme = {
      name = "gruvbox-dark";
      package = pkgs.gruvbox-dark-gtk;
    };
    iconTheme.package = pkgs.gruvbox-dark-icons-gtk;
    iconTheme.name = "Gruvbox-Dark";
  };

  home.file = {
    ".config/swaync/config.json".source = ../../home/wm/swaync/config.json;
    ".config/swaync/style.css".source = ../../home/wm/swaync/style.css;
  };

  programs = {
    fuzzel = {
      enable = true;
      settings = {
        colors = with config.colorScheme.palette; {
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
    waybar = {
      enable = true;
      style = ../../home/wm/waybar/style.css;
      settings.mainBar = builtins.fromJSON (builtins.readFile ../../home/wm/waybar/config.json);
    };
  };

  home.activation.reloadHyprland = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    hyprctl reload
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    settings = {
      exec = [ "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1" ];
      general = {
        layout = "dwindle";
        "col.active_border" = with config.colorScheme.palette; "rgba(${base09}ee) rgba(${base0A}ee) 45deg";
      };
      "$mainMod" = "SUPER";
      bind = [
        "$mainMod, Q, exec, foot"
        "$mainMod, E, exec, emacsclient -c"
        "$mainMod, H, movefocus, l"
        "$mainMod, L, movefocus, r"
        "$mainMod, K, movefocus, u"
        "$mainMod, J, movefocus, d"
      ];

      decoration.shadow = {
        enabled = true;
        range = 4;
        render_power = 3;
        color = "rgba(1a1a1aee)";
      };

    };
    extraConfig = builtins.readFile ../../home/wm/hyprland.conf;
  };
}
