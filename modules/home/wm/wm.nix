{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [ inputs.nix-colors.homeManagerModules.default ];

  colorScheme = inputs.nix-colors.colorSchemes.gruvbox-material-dark-soft;
  #   colorScheme = nix-colors-lib.colorSchemeFromPicture {
  #     path = wallpaper;
  #     kind = "dark";
  #   };

  home = {
    packages = with pkgs; [ swaynotificationcenter ];

    file = {
      ".config/swaync/config.json".source = ../../home/wm/swaync/config.json;
      ".config/swaync/style.css".source = ../../home/wm/swaync/style.css;
    };

    activation.reloadHyprland = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      hyprctl reload
    '';
  };

  gtk = {
    enable = true;
    theme = {
      name = "gruvbox-dark";
      package = pkgs.gruvbox-dark-gtk;
    };
    iconTheme.package = pkgs.gruvbox-dark-icons-gtk;
    iconTheme.name = "Gruvbox-Dark";
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
        key-bindings = {
          delete-line-forward = "none"; # Unmap default Control+k binding
          next = "Control+j";
          prev = "Control+k";
        };
      };
    };
    waybar = {
      enable = true;
      style = ../../home/wm/waybar/style.css;
      settings.mainBar = builtins.fromJSON (builtins.readFile ../../home/wm/waybar/config.json);
    };
  };

  services.wlsunset = {
    enable = false;
  };

  # services.hyprsunset = {
  #   enable = true;
  #   transitions = {
  #     sunset = {
  #       calendar = "18:45:00";  # Approximate Dallas winter sunset
  #       requests = [
  #         [ "temperature" "4000" ]
  #         [ "gamma" "0.9" ]
  #       ];
  #     };
  #     sunrise = {
  #       calendar = "07:30:00";  # Approximate Dallas winter sunrise
  #       requests = [
  #         [ "temperature" "6500" ]
  #         [ "gamma" "1.0" ]
  #       ];
  #     };
  #   };
  # };

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
        "$mainMod SHIFT, Q, exec, foot zellij"
        "$mainMod, E, exec, emacsclient -c"
        "$mainMod, B, exec, claude-desktop"
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
