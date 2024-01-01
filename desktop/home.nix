{ config, pkgs, lib, nix-colors, ... }:
let
  nix-colors-lib = nix-colors.lib.contrib {inherit pkgs; };
  wallpaper = ./wallpapers/revachol.jpg;
in
{
  imports =
  [ # Include the results of the hardware scan.
    ./emacs.nix
    ./home-gaming.nix
    nix-colors.homeManagerModules.default
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

  # Theming
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

  qt = {
    enable = true;
    platformTheme = "gtk";
    style.name = "adwaita-dark";
#     style.name = "Gruvbox"
  };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    swaynotificationcenter
    gparted
  ];

  home.file = with config.colorScheme.colors; {

    ".config/waybar/config.jsonc".source = ../waybar/config.jsonc;
    ".config/waybar/style.css".source = ../waybar/style.css;
    ".config/swaync/config.json".source = ../swaync/config.json;
    ".config/swaync/style.css".source = ../swaync/style.css;
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ammar/etc/profile.d/hm-session-vars.sh
  #


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

    bash = {
      enable = true;
    };
    
    git = {
      enable = true;
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
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

  # services.mako = with config.colorScheme.colors; {
  #   enable = true;
  #   anchor = "top-center";
  #   backgroundColor = "#${base00}";
  #   borderColor = "#${base09}";
  #   borderRadius = 5;
  #   borderSize = 2;
  #   textColor = "#${base05}";
  #   layer = "overlay";
  # };

  wayland.windowManager.hyprland = with config.colorScheme.colors; {
    enable = true;
    extraConfig = ''
      # See https://wiki.hyprland.org/Configuring/Monitors/
      monitor=,highrr,auto,1,vrr,2
      exec-once = corectrl
      exec-once = swaybg -i ${wallpaper} -m fit
      exec-once = ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
      exec-once = gamescope -e -W 5120 -H 1440 -f -r 240 --adaptive-sync -- steam
      general {
        
        # See https://wiki.hyprland.org/Configuring/Variables/ for more
        gaps_in = 5
        gaps_out = 20
        border_size = 2
        col.active_border = rgba(${base09}ee) rgba(${base0A}ee) 45deg
        col.inactive_border = rgba(595959aa)
        no_cursor_warps = true
        layout = master

        # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
        allow_tearing = false
      }
    '' + builtins.readFile ../hyprland.conf;

  };

  xdg = {
    configFile."mimeapps.list".force = true;
    mimeApps = {
      enable = true;

      defaultApplications = {
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/about" = "firefox.desktop";
        "x-scheme-handler/unknown" = "firefox.desktop";
        "inode/directory" = "thunar.desktop";
      };
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
