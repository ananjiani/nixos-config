# Dendritic Gaming Module
# Unified gaming configuration spanning system-level services (Steam, gamemode,
# gamescope) and user-level tools (MangoHUD, Vesktop, Heroic, Wine, etc.).
_:

{
  # ── NixOS class ──────────────────────────────────────────────────────
  flake.aspects.gaming.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.gaming;
    in
    {
      options.gaming = {
        enable = lib.mkEnableOption "gaming system services and packages";
      };

      config = lib.mkIf cfg.enable {
        programs = {
          steam = {
            enable = true;
            extraCompatPackages = with pkgs; [ proton-ge-bin ];
            package = pkgs.steam.override {
              extraEnv = { };
              extraLibraries =
                pkgs: with pkgs; [
                  xorg.libXcursor
                  xorg.libXi
                  xorg.libXinerama
                  xorg.libXScrnSaver
                  libpng
                  libpulseaudio
                  libvorbis
                  stdenv.cc.cc.lib
                  libkrb5
                  keyutils
                ];
            };
          };
          gamemode.enable = true;
          gamemode.enableRenice = true;
        };

        programs.gamescope.enable = true;
        programs.gamescope.capSysNice = true;

        environment.systemPackages = with pkgs; [
          steamtinkerlaunch
          yad
          gamescope-wsi
        ];
      };
    };

  # ── Home Manager class ─────────────────────────────────────────────
  flake.aspects.gaming.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.gaming;
    in
    {
      options.gaming = {
        enable = lib.mkEnableOption "gaming user-level tools and launchers";

        syncthing = {
          enable = lib.mkEnableOption "Syncthing save sync";
        };

        ludusavi = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = cfg.enable;
            description = "Ludusavi save backup (auto-enabled when gaming is on)";
          };
          backupPath = lib.mkOption {
            type = lib.types.str;
            default = "${config.home.homeDirectory}/Games/Saves";
            description = "Path for Ludusavi backups (set per-host for subdirectory separation)";
          };
          timerInterval = lib.mkOption {
            type = lib.types.str;
            default = "hourly";
            description = "Systemd timer OnCalendar interval";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        home.sessionVariables = {
          DXVK_HDR = "1";
          WINE_LARGE_ADDRESS_AWARE = "1";
        };

        home.packages =
          with pkgs;
          [
            gpu-screen-recorder
            gpu-screen-recorder-gtk
            wine-wayland
            protontricks
            winetricks
            heroic
            hydralauncher
            umu-launcher
          ]
          ++ lib.optionals cfg.ludusavi.enable [
            ludusavi
          ]
          ++ [
            boilr
            protonup-qt
          ];

        # Syncthing for game save sync (Desktop ↔ Deck ↔ theoden)
        services.syncthing = lib.mkIf cfg.syncthing.enable {
          enable = true;
          settings = {
            folders."game-saves" = {
              path = "${config.home.homeDirectory}/Games/Saves";
              id = "game-saves";
              # Devices are paired via web UI (device IDs are per-install)
            };
          };
        };

        # Ludusavi systemd user timer for automated save backups
        systemd.user = lib.mkIf cfg.ludusavi.enable {
          services.ludusavi-backup = {
            Unit = {
              Description = "Ludusavi save backup";
              Documentation = "https://github.com/mtkennerly/ludusavi";
              After = [ "network-online.target" ];
              Wants = [ "network-online.target" ];
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${pkgs.ludusavi}/bin/ludusavi --try-manifest-update backup --path ${cfg.ludusavi.backupPath} --force";
            };
          };
          timers.ludusavi-backup = {
            Unit = {
              Description = "Ludusavi save backup timer";
            };
            Install = {
              WantedBy = [ "timers.target" ];
            };
            Timer = {
              OnCalendar = cfg.ludusavi.timerInterval;
              Persistent = true;
            };
          };
        };

        programs = {
          mangohud = {
            enable = true;
            settings = {
              cpu_stats = true;
              cpu_temp = true;
              # core_load = true;
              gpu_stats = true;
              gpu_temp = true;
              fps = true;
              frametime = true;
              frame_timing = true;
              hdr = true;
            };
          };
          vesktop = {
            enable = true;
            settings = {
              discordBranch = "stable";
              transparencyOption = "none";
              tray = true;
              autoStartMinimized = true;
              hardwareAcceleration = true;
              minimizeToTray = true;
            };
            vencord.settings = {
              useQuickCss = true;
              plugins = {
                ClearURLs.enable = true;
                SilentTyping.enable = true;
                VoiceChatDoubleClick.enable = true;
                WebKeybinds.enable = true;
                QuickReply.enable = true;
                NoTypingAnimation.enable = true;
                MessageLogger.enable = true;
                BetterFolders.enable = true;
              };
            };
          };
        };
      };
    };
}
