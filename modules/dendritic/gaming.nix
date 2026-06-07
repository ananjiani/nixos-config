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

      # Wrapper that excludes cloud-save games, rescues DRM-free/non-Steam games
      ludusaviBackupWrapper = pkgs.writers.writePython3Bin "ludusavi-backup-wrapper" {
        libraries = with pkgs.python3Packages; [ pyyaml ];
        flakeIgnore = [ "E501" ];
      } ''
        import json, subprocess, os, sys, re, glob

        CONFIG_PATH = os.path.expanduser("~/.config/ludusavi/config.yaml")
        STEAM_LIBS = [
            os.path.expanduser("~/.local/share/Steam/steamapps"),
            "/mnt/nvme/SteamLibrary/steamapps",
        ]
        LUDUSAVI = "${pkgs.ludusavi}/bin/ludusavi"

        def load_config():
            import yaml
            with open(CONFIG_PATH) as f:
                return yaml.safe_load(f)

        def save_config(config):
            import yaml
            with open(CONFIG_PATH, "w") as f:
                yaml.dump(config, f, default_flow_style=False, sort_keys=False)

        def run_preview(backup_path, cloud_exclude):
            config = load_config()
            config["backup"]["filter"]["cloud"] = {
                "exclude": cloud_exclude,
                "epic": True, "gog": True, "origin": True, "steam": True, "uplay": True,
            }
            save_config(config)
            result = subprocess.run(
                [LUDUSAVI, "--try-manifest-update", "backup", "--preview",
                 "--path", "/tmp/ludusavi-wrapper-empty", "--api"],
                capture_output=True, text=True, timeout=120
            )
            return set(json.loads(result.stdout).get("games", {}).keys())

        def build_compatdata_map(backup_path):
            import yaml
            name_to_cid = {}
            for d in glob.glob(f"{backup_path}/*/"):
                mapping = os.path.join(d, "mapping.yaml")
                if not os.path.exists(mapping):
                    continue
                with open(mapping) as f:
                    data = yaml.safe_load(f)
                game_name = data.get("name", "")
                for fpath in data.get("backups", [{}])[0].get("files", {}):
                    m = re.search(r"compatdata/(\d+)", fpath)
                    if m:
                        name_to_cid[game_name] = m.group(1)
                        break
            return name_to_cid

        def has_appmanifest(cid):
            if not cid:
                return False
            for lib in STEAM_LIBS:
                if os.path.exists(f"{lib}/appmanifest_{cid}.acf"):
                    return True
            return False

        # ── Main ──
        backup_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Games/Saves/ammars-pc")

        all_games = run_preview(backup_path, cloud_exclude=False)
        non_cloud = run_preview(backup_path, cloud_exclude=True)
        cloud_games = all_games - non_cloud

        name_to_cid = build_compatdata_map(backup_path)

        rescued = set()
        for game in cloud_games:
            cid = name_to_cid.get(game)
            if cid and not has_appmanifest(cid):
                rescued.add(game)

        # Live-service games with server-side state — no local saves to back up
        force_exclude = {
            "Lethal Company", "MultiVersus", "Payday 3",
            "The Finals", "Webfishing", "Marvel Rivals",
            "Sea of Thieves",
        }

        ignored = sorted((cloud_games - rescued) | force_exclude)
        config = load_config()
        config["backup"]["ignoredGames"] = ignored
        config["backup"]["filter"]["cloud"] = {
            "exclude": True,
            "epic": True, "gog": True, "origin": True, "steam": True, "uplay": True,
        }
        save_config(config)

        os.execvp(LUDUSAVI, [
            LUDUSAVI, "--try-manifest-update", "backup",
            "--path", backup_path, "--force"
        ])
      '';
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
              ExecStart = "${ludusaviBackupWrapper}/bin/ludusavi-backup-wrapper ${cfg.ludusavi.backupPath}";
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
