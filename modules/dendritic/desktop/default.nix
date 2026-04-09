# Dendritic Desktop Aspect Module
# Compositor-agnostic desktop plumbing with Hyprland and niri compositor support.
# Both compositors can be enabled simultaneously — SDDM session picker selects which to launch.
_:
let
  scriptsDir = ./scripts;
in
{
  flake.aspects.desktop = {
    # ── NixOS class ──────────────────────────────────────────────────────
    nixos =
      {
        pkgs,
        pkgs-stable,
        lib,
        config,
        inputs,
        ...
      }:
      let
        cfg = config.desktop;
        anyDesktop = cfg.hyprland.enable || cfg.niri.enable;
      in
      {
        imports = [ inputs.niri.nixosModules.niri ];

        options.desktop = {
          hyprland.enable = lib.mkEnableOption "Hyprland compositor";
          niri.enable = lib.mkEnableOption "niri compositor";
        };

        config = lib.mkIf anyDesktop (
          lib.mkMerge [
            # ── Shared desktop plumbing ────────────────────────────────
            {
              programs = {
                dconf.enable = true;
                xwayland.enable = true;
              };

              xdg.portal = {
                enable = true;
                extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
              };

              # xremap uinput/group setup
              hardware.uinput.enable = true;
              users.groups = {
                uinput.members = [ "ammar" ];
                input.members = [ "ammar" ];
              };

              environment.systemPackages = with pkgs-stable; [
                libreoffice
                imagemagick
                remmina
                wl-clipboard
                pavucontrol
                light
                libnotify
                copyq
                wlogout
                swaybg
                grim
                slurp
                swappy
                polkit_gnome
              ];

              services = {
                libinput.enable = true;

                displayManager.sddm = {
                  enable = true;
                  wayland.enable = true;
                };

                xserver = {
                  enable = true;
                  xkb.layout = "us";
                };

                pipewire = {
                  enable = true;
                  wireplumber.enable = true;
                  alsa = {
                    enable = true;
                    support32Bit = true;
                  };
                  pulse.enable = true;
                };

                printing.enable = true;

                avahi = {
                  enable = true;
                  nssmdns4 = true;
                  openFirewall = true;
                };

                upower.enable = true;
                flatpak.enable = true;
                dbus.enable = true;
                gvfs.enable = true;
              };
            }

            # ── Hyprland NixOS ─────────────────────────────────────────
            (lib.mkIf cfg.hyprland.enable {
              programs = {
                hyprland.enable = true;
                hyprland.package = pkgs.hyprland;
              };

              xdg.portal = {
                extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
                config = {
                  common.default = [
                    "hyprland"
                    "gtk"
                  ];
                  hyprland.default = [
                    "hyprland"
                    "gtk"
                  ];
                };
              };

              nix.settings = {
                trusted-substituters = [ "https://hyprland.cachix.org" ];
                trusted-public-keys = [
                  "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
                ];
              };

              environment.systemPackages = with pkgs-stable; [
                hyprpicker
                nwg-displays
                wlr-randr
              ];
            })

            # ── niri NixOS ─────────────────────────────────────────────
            (lib.mkIf cfg.niri.enable {
              programs.niri.enable = true;

              xdg.portal.config = {
                niri.default = [
                  "gnome"
                  "gtk"
                ];
              };

              environment.systemPackages = [ pkgs.xdg-desktop-portal-gnome ];
            })
          ]
        );
      };

    # ── Home Manager class ─────────────────────────────────────────────
    homeManager =
      {
        pkgs,
        lib,
        config,
        inputs,
        ...
      }:
      let
        cfg = config.desktop;
        anyDesktop = cfg.hyprland.enable || cfg.niri.enable;

        # Shared waybar module configs (used by both hyprlandBar and niriBar)
        waybarSharedModules = {
          "idle_inhibitor" = {
            format = "{icon}";
            format-icons = {
              activated = "";
              deactivated = "";
            };
          };
          clock = {
            format = "{:%H:%M  %a %d %b}";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            format-alt = "{:%Y-%m-%d %H:%M}";
          };
          cpu = {
            format = "{usage}% ";
            tooltip = false;
          };
          memory = {
            format = "{}% ";
          };
          temperature = {
            critical-threshold = 80;
            format = "{temperatureC}°C {icon}";
            format-icons = [
              ""
              ""
              ""
            ];
          };
          backlight = {
            format = "{percent}% {icon}";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
            ];
          };
          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{capacity}% {icon}";
            format-charging = "{capacity}% ";
            format-plugged = "{capacity}% ";
            format-alt = "{time} {icon}";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
            ];
          };
          "battery#bat2" = {
            bat = "BAT2";
          };
          pulseaudio = {
            format = "{volume}% {icon} {format_source}";
            format-bluetooth = "{volume}% {icon} {format_source}";
            format-bluetooth-muted = " {icon} {format_source}";
            format-muted = " {format_source}";
            format-source = "{volume}% ";
            format-source-muted = "";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = [
                ""
                ""
                ""
              ];
            };
            on-click = "pavucontrol";
          };
          tray = {
            spacing = 10;
          };
          "custom/media" = {
            format = "{icon} {}";
            return-type = "json";
            max-length = 40;
            format-icons = {
              spotify = "";
              default = "🎜";
            };
            escape = true;
            exec = "$HOME/.config/waybar/mediaplayer.py 2> /dev/null";
          };
          "custom/notification" = {
            tooltip = false;
            format = "{} {icon}";
            format-icons = {
              notification = "<span foreground='red'><sup></sup></span>";
              none = "";
              dnd-notification = "<span foreground='red'><sup></sup></span>";
              dnd-none = "";
              inhibited-notification = "<span foreground='red'><sup></sup></span>";
              inhibited-none = "";
              dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
              dnd-inhibited-none = "";
            };
            return-type = "json";
            exec-if = "which swaync-client";
            exec = "swaync-client -swb";
            on-click = "swaync-client -t -sw";
            on-click-right = "swaync-client -d -sw";
            escape = true;
          };
        };
      in
      {
        imports = [
          inputs.nix-colors.homeManagerModules.default
          inputs.niri.homeModules.niri
        ];

        options.desktop = {
          hyprland.enable = lib.mkEnableOption "Hyprland compositor";
          niri.enable = lib.mkEnableOption "niri compositor";

          startupApps = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "copyq"
              "swaync"
              "signal-desktop --start-in-tray"
              "element-desktop --hidden"
              "claude-desktop"
              "pear-desktop"
              "vesktop"
            ];
            description = "Apps to launch on compositor startup";
          };

          wallpaper = {
            enable = lib.mkEnableOption "wallpaper";
            path = lib.mkOption {
              type = lib.types.path;
              default = ../../../hosts/_profiles/workstation/wallpapers/revachol.jpg;
              description = "Path to the wallpaper image";
            };
            mode = lib.mkOption {
              type = lib.types.enum [
                "fill"
                "fit"
                "center"
                "stretch"
                "tile"
              ];
              default = "fill";
              description = "Wallpaper display mode";
            };
          };
        };

        config = lib.mkIf anyDesktop (
          lib.mkMerge [
            # ── Shared HM config ─────────────────────────────────────
            {
              colorScheme = inputs.nix-colors.colorSchemes.gruvbox-material-dark-soft;

              home = {
                packages = [ pkgs.swaynotificationcenter ];

                file = {
                  ".config/swaync/config.json".source = ./swaync/config.json;
                  ".config/swaync/style.css".source = ./swaync/style.css;
                };

                sessionVariables = {
                  XCURSOR_SIZE = "24";
                  NIXOS_OZONE_WL = "1";
                };
              };

              gtk = {
                enable = true;
                theme = {
                  name = "gruvbox-dark";
                  package = pkgs.gruvbox-dark-gtk;
                };
                iconTheme = {
                  package = pkgs.gruvbox-dark-icons-gtk;
                  name = "Gruvbox-Dark";
                };
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
                      delete-line-forward = "none";
                      next = "Control+j";
                      prev = "Control+k";
                    };
                  };
                };

                waybar = {
                  enable = true;
                  style = ./waybar/style.css;
                };
              };
            }

            # ── Hyprland HM ─────────────────────────────────────────
            (lib.mkIf cfg.hyprland.enable {
              home.activation.reloadHyprland = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
                hyprctl reload
              '';

              wayland.windowManager.hyprland = {
                enable = true;
                package = pkgs.hyprland;
                settings = {
                  "$mainMod" = "SUPER";

                  exec = [ "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1" ];

                  exec-once =
                    cfg.startupApps
                    ++ lib.optional cfg.wallpaper.enable "swaybg -i ${cfg.wallpaper.path} -m ${cfg.wallpaper.mode}"
                    ++ [
                      "waybar -b hyprlandBar"
                      "${pkgs.bash}/bin/bash ${scriptsDir}/weekday-work-edge.sh"
                      "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
                    ];

                  general = {
                    gaps_in = 5;
                    gaps_out = 20;
                    border_size = 2;
                    "col.inactive_border" = "rgba(595959aa)";
                    "col.active_border" = with config.colorScheme.palette; "rgba(${base09}ee) rgba(${base0A}ee) 45deg";
                    allow_tearing = false;
                    layout = "dwindle";
                  };

                  input = {
                    kb_layout = "us";
                    follow_mouse = 1;
                    touchpad = {
                      natural_scroll = false;
                    };
                    sensitivity = 0;
                  };

                  decoration = {
                    rounding = 10;
                    blur = {
                      enabled = true;
                      size = 3;
                      passes = 1;
                      vibrancy = 0.1696;
                    };
                    shadow = {
                      enabled = true;
                      range = 4;
                      render_power = 3;
                      color = "rgba(1a1a1aee)";
                    };
                  };

                  animations = {
                    enabled = true;
                    bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
                    animation = [
                      "windows, 1, 7, myBezier"
                      "windowsOut, 1, 7, default, popin 80%"
                      "border, 1, 10, default"
                      "borderangle, 1, 8, default"
                      "fade, 1, 7, default"
                      "workspaces, 1, 6, default"
                    ];
                  };

                  dwindle = {
                    pseudotile = true;
                    preserve_split = true;
                  };

                  master = {
                    new_on_top = false;
                    orientation = "center";
                  };

                  misc = {
                    force_default_wallpaper = 0;
                  };

                  windowrule = [
                    "suppressevent maximize, class:.*"
                  ];

                  windowrulev2 = [
                    "stayfocused, title:^()$, class:^(steam)$"
                    "minsize 1 1, title:^()$, class:^(steam)$"
                    "float, class:copyq"
                    "float, class:pavucontrol"
                  ];

                  bind = [
                    # Terminal & apps
                    "$mainMod, Q, exec, foot"
                    "$mainMod SHIFT, Q, exec, foot zellij"
                    "$mainMod, E, exec, emacsclient -c"
                    "$mainMod, B, exec, claude-desktop"
                    "$mainMod, R, exec, fuzzel"
                    "$mainMod, F, exec, brave"
                    "$mainMod SHIFT, F, exec, mullvad-browser"
                    "$mainMod ALT, F, exec, tor-browser"

                    # Window management
                    "$mainMod, C, killactive,"
                    "$mainMod, V, togglefloating,"
                    "$mainMod, P, pseudo,"
                    "$mainMod, I, togglesplit,"
                    "$mainMod, W, layoutmsg, swapwithmaster"
                    "$mainMod, N, exec, swaync-client -t -sw"

                    # Layout switching
                    "SUPER, Y, exec, hyprctl keyword general:layout \"dwindle\""
                    "SUPERSHIFT, Y, exec, hyprctl keyword general:layout \"master\""

                    # Focus movement (vim keys)
                    "$mainMod, H, movefocus, l"
                    "$mainMod, L, movefocus, r"
                    "$mainMod, K, movefocus, u"
                    "$mainMod, J, movefocus, d"

                    # Focus movement (arrow keys)
                    "$mainMod, left, movefocus, l"
                    "$mainMod, right, movefocus, r"
                    "$mainMod, up, movefocus, u"
                    "$mainMod, down, movefocus, d"

                    # Move windows
                    "$mainMod CTRL, H, movewindow, l"
                    "$mainMod CTRL, L, movewindow, r"
                    "$mainMod CTRL, K, movewindow, u"
                    "$mainMod CTRL, J, movewindow, d"
                    "$mainMod CTRL, I, togglesplit"
                    "$mainMod CTRL, N, swapnext"
                    "$mainMod CTRL, P, swapnext, prev"

                    # Switch workspaces
                    "$mainMod, 1, workspace, 1"
                    "$mainMod, 2, workspace, 2"
                    "$mainMod, 3, workspace, 3"
                    "$mainMod, 4, workspace, 4"
                    "$mainMod, 5, workspace, 5"
                    "$mainMod, 6, workspace, 6"
                    "$mainMod, 7, workspace, 7"
                    "$mainMod, 8, workspace, 8"
                    "$mainMod, 9, workspace, 9"

                    # Move window to workspace
                    "$mainMod SHIFT, 1, movetoworkspace, 1"
                    "$mainMod SHIFT, 2, movetoworkspace, 2"
                    "$mainMod SHIFT, 3, movetoworkspace, 3"
                    "$mainMod SHIFT, 4, movetoworkspace, 4"
                    "$mainMod SHIFT, 5, movetoworkspace, 5"
                    "$mainMod SHIFT, 6, movetoworkspace, 6"
                    "$mainMod SHIFT, 7, movetoworkspace, 7"
                    "$mainMod SHIFT, 8, movetoworkspace, 8"
                    "$mainMod SHIFT, 9, movetoworkspace, 9"
                    "$mainMod SHIFT, 0, movetoworkspace, 10"

                    # Move window silently to workspace
                    "$mainMod ALT, 1, movetoworkspacesilent, 1"
                    "$mainMod ALT, 2, movetoworkspacesilent, 2"
                    "$mainMod ALT, 3, movetoworkspacesilent, 3"
                    "$mainMod ALT, 4, movetoworkspacesilent, 4"
                    "$mainMod ALT, 5, movetoworkspacesilent, 5"
                    "$mainMod ALT, 6, movetoworkspacesilent, 6"
                    "$mainMod ALT, 7, movetoworkspacesilent, 7"
                    "$mainMod ALT, 8, movetoworkspacesilent, 8"
                    "$mainMod ALT, 9, movetoworkspacesilent, 9"
                    "$mainMod ALT, 0, movetoworkspacesilent, 10"

                    # Navigate workspaces
                    "$mainMod SHIFT, H, workspace, e-1"
                    "$mainMod SHIFT, L, workspace, e+1"
                    "$mainMod, Tab, workspace, previous"

                    # Scratchpad
                    "$mainMod, S, togglespecialworkspace, magic"
                    "$mainMod SHIFT, S, movetoworkspace, special:magic"

                    # Scroll through workspaces
                    "$mainMod, mouse_down, workspace, e+1"
                    "$mainMod, mouse_up, workspace, e-1"

                    # Screenshots
                    ", Print, exec, grim -g \"$(slurp)\" - | convert - -shave 1x1 PNG:- | wl-copy"
                    "ctrl, Print, exec, grim - | convert - -shave 1x1 PNG:- | wl-copy"
                    "$mainMod, Print, exec, wl-paste | swappy -f -"

                    # Whisper dictation
                    "$mainMod, D, exec, bash ${scriptsDir}/whisper-toggle.sh"

                    # Media controls
                    "$mainMod, space, exec, playerctl play-pause"
                    "$mainMod, bracketright, exec, playerctl next"
                    "$mainMod, bracketleft, exec, playerctl previous"

                    # Volume controls
                    "$mainMod, equal, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
                    "$mainMod, minus, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
                    "$mainMod, 0, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"

                    # Audio device switcher
                    "$mainMod, A, exec, bash ${scriptsDir}/audio-switch.sh"

                    # Window switcher
                    "$mainMod, O, exec, bash ${scriptsDir}/window-switcher.sh"

                    # Git project switcher
                    "$mainMod, G, exec, bash ${scriptsDir}/git-project-switcher.sh"
                  ];

                  bindm = [
                    "$mainMod, mouse:272, movewindow"
                    "$mainMod, mouse:273, resizewindow"
                  ];
                };
              };

              programs.waybar.settings.hyprlandBar = waybarSharedModules // {
                name = "hyprlandBar";
                layer = "top";
                height = 30;
                spacing = 4;
                modules-left = [
                  "hyprland/workspaces"
                  "hyprland/mode"
                  "hyprland/scratchpad"
                  "custom/media"
                  "hyprland/window"
                ];
                modules-center = [
                  "clock"
                  "custom/notification"
                ];
                modules-right = [
                  "idle_inhibitor"
                  "pulseaudio"
                  "cpu"
                  "memory"
                  "temperature"
                  "backlight"
                  "battery"
                  "tray"
                ];
                "hyprland/workspaces" = {
                  disable-scroll = true;
                  all-outputs = false;
                  warp-on-scroll = false;
                  format = "{icon}";
                  format-icons = {
                    "1" = "1";
                    "2" = "2";
                    "3" = "3";
                    "4" = "4 󰙯";
                    "5" = "5 󰕧";
                  };
                  active-only = false;
                  show-special = false;
                  format-window-separator = " ";
                  window-rewrite-default = "";
                  window-rewrite = {
                    "title<.*youtube.*>" = "";
                    "class<firefox>" = "";
                    "class<kitty>" = "";
                    "class<foot>" = "";
                    "class<Alacritty>" = "";
                    "class<code>" = "󰨞";
                    "class<Code>" = "󰨞";
                    "class<emacs>" = "";
                    "class<Emacs>" = "";
                    "title<.*vim.*>" = "";
                    "class<discord>" = "󰙯";
                    "class<signal>" = "";
                    "class<Signal>" = "";
                    "class<element>" = "󰭻";
                    "class<Element>" = "󰭻";
                    "class<webcord>" = "󰙯";
                    "class<WebCord>" = "󰙯";
                    "class<claude-desktop>" = "󰚩";
                    "class<pear-desktop>" = "";
                    "class<spotify>" = "";
                    "class<Spotify>" = "";
                    "class<steam>" = "";
                    "class<pavucontrol>" = "󰕾";
                    "class<Slack>" = "󰒱";
                    "class<obsidian>" = "󰇈";
                    "class<Obsidian>" = "󰇈";
                  };
                };
                "hyprland/mode" = {
                  format = "<span style=\"italic\">{}</span>";
                };
                "hyprland/scratchpad" = {
                  format = "{icon} {count}";
                  show-empty = false;
                  format-icons = [
                    ""
                    ""
                  ];
                  tooltip = true;
                  tooltip-format = "{app}: {title}";
                };
              };
            })

            # ── niri HM ─────────────────────────────────────────────
            (lib.mkIf cfg.niri.enable {
              programs.niri.settings = {
                input = {
                  keyboard.xkb.layout = "us";
                  touchpad = {
                    tap = true;
                    natural-scroll = false;
                  };
                };

                layout = {
                  gaps = 20;
                  border = {
                    width = 2;
                  };
                };

                spawn-at-startup =
                  (map (app: {
                    command = [
                      "bash"
                      "-c"
                      app
                    ];
                  }) cfg.startupApps)
                  ++ lib.optional cfg.wallpaper.enable {
                    command = [
                      "swaybg"
                      "-i"
                      (toString cfg.wallpaper.path)
                      "-m"
                      cfg.wallpaper.mode
                    ];
                  }
                  ++ [
                    {
                      command = [
                        "waybar"
                        "-b"
                        "niriBar"
                      ];
                    }
                  ];

                binds = with config.lib.niri.actions; {
                  "Mod+Return".action = spawn "foot";
                  "Mod+Shift+Return".action = spawn "foot" "zellij";
                  "Mod+E".action = spawn "emacsclient" "-c";
                  "Mod+B".action = spawn "claude-desktop";
                  "Mod+R".action = spawn "fuzzel";
                  "Mod+F".action = spawn "brave";
                  "Mod+C".action = close-window;
                  "Mod+V".action = toggle-window-floating;

                  # Focus movement
                  "Mod+H".action = focus-column-left;
                  "Mod+L".action = focus-column-right;
                  "Mod+K".action = focus-window-up;
                  "Mod+J".action = focus-window-down;

                  # Move windows
                  "Mod+Ctrl+H".action = move-column-left;
                  "Mod+Ctrl+L".action = move-column-right;
                  "Mod+Ctrl+K".action = move-window-up;
                  "Mod+Ctrl+J".action = move-window-down;

                  # Workspaces
                  "Mod+1".action = focus-workspace 1;
                  "Mod+2".action = focus-workspace 2;
                  "Mod+3".action = focus-workspace 3;
                  "Mod+4".action = focus-workspace 4;
                  "Mod+5".action = focus-workspace 5;
                  "Mod+6".action = focus-workspace 6;
                  "Mod+7".action = focus-workspace 7;
                  "Mod+8".action = focus-workspace 8;
                  "Mod+9".action = focus-workspace 9;
                  "Mod+Shift+1".action = move-window-to-workspace 1;
                  "Mod+Shift+2".action = move-window-to-workspace 2;
                  "Mod+Shift+3".action = move-window-to-workspace 3;
                  "Mod+Shift+4".action = move-window-to-workspace 4;
                  "Mod+Shift+5".action = move-window-to-workspace 5;
                  "Mod+Shift+6".action = move-window-to-workspace 6;
                  "Mod+Shift+7".action = move-window-to-workspace 7;
                  "Mod+Shift+8".action = move-window-to-workspace 8;
                  "Mod+Shift+9".action = move-window-to-workspace 9;

                  # Screenshots
                  "Print".action = screenshot;
                  "Mod+Print".action = screenshot-window;

                  # Media controls
                  "Mod+Space".action = spawn "playerctl" "play-pause";
                  "Mod+BracketRight".action = spawn "playerctl" "next";
                  "Mod+BracketLeft".action = spawn "playerctl" "previous";

                  # Volume
                  "Mod+Equal".action = spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+";
                  "Mod+Minus".action = spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";
                  "Mod+0".action = spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";

                  # Audio device switcher
                  "Mod+A".action = spawn "bash" "${scriptsDir}/audio-switch.sh";

                  # Whisper dictation
                  "Mod+D".action = spawn "bash" "${scriptsDir}/whisper-toggle.sh";

                  # Git project switcher
                  "Mod+G".action = spawn "bash" "${scriptsDir}/git-project-switcher.sh";
                };
              };

              programs.waybar.settings.niriBar = waybarSharedModules // {
                name = "niriBar";
                layer = "top";
                height = 30;
                spacing = 4;
                modules-left = [
                  "niri/workspaces"
                  "custom/media"
                  "niri/window"
                ];
                modules-center = [
                  "clock"
                  "custom/notification"
                ];
                modules-right = [
                  "idle_inhibitor"
                  "pulseaudio"
                  "cpu"
                  "memory"
                  "temperature"
                  "backlight"
                  "battery"
                  "tray"
                ];
              };
            })
          ]
        );
      };
  };
}
