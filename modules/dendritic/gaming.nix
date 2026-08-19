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
              extraArgs = "-pipewire";
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
          gamescope = {
            enable = true;
            capSysNice = false;
          };
        };

        services.udev.extraRules = ''
          # 8BitDo Ultimate 2 Wireless - 2.4GHz/Dongle (DInput: gyro + back buttons)
          KERNEL=="hidraw*", ATTRS{idProduct}=="6012", ATTRS{idVendor}=="2dc8", MODE="0660", TAG+="uaccess"
          # 8BitDo Ultimate 2 Wireless - Bluetooth
          KERNEL=="hidraw*", KERNELS=="*2DC8:6012*", MODE="0660", TAG+="uaccess"
        '';

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

      sources = import ../../_sources/generated.nix {
        inherit (pkgs)
          fetchurl
          fetchFromGitHub
          fetchgit
          dockerTools
          ;
      };

      # Shared UMU Proton launcher: pin installer via nvfetcher, writable prefix,
      # first-install flock + silent NSIS /S, optional one-shot winetricks.
      mkUmuLauncher =
        {
          id,
          command ? id,
          desktopName,
          prefix,
          source,
          launcherPath,
          winetricks ? [ ],
          # OctoLauncher only; omit elsewhere to keep .desktop identical.
          startupWMClass ? null,
        }:
        let
          launcher = "${prefix}/${launcherPath}";
          winetricksMarker = "${prefix}/.${id}-winetricks-v1";
          wrapper = pkgs.writeShellApplication {
            name = command;
            runtimeInputs = [
              pkgs.umu-launcher
              pkgs.util-linux
            ]
            ++ lib.optionals (winetricks != [ ]) [ pkgs.winetricks ];
            text = ''
              export WINEPREFIX=${lib.escapeShellArg prefix}
              export GAMEID=umu-${id}
              export PROTON_VERB=waitforexitandrun
              launcher=${lib.escapeShellArg launcher}
              ${lib.optionalString (winetricks != [ ]) ''
                marker=${lib.escapeShellArg winetricksMarker}
              ''}
              if [[ ! -f $launcher ]]; then
                exec 9>"$XDG_RUNTIME_DIR/${command}-install.lock"
                flock 9
                if [[ ! -f $launcher ]]; then
                  /run/wrappers/bin/mullvad-exclude umu-run ${source.src} /S
                fi
                flock -u 9
                exec 9>&-
                if [[ ! -f $launcher ]]; then
                  echo "${command}: install failed; missing $launcher" >&2
                  exit 1
                fi
              fi
              ${lib.optionalString (winetricks != [ ]) ''
                if [[ ! -f $marker ]]; then
                  exec 9>"$XDG_RUNTIME_DIR/${command}-winetricks.lock"
                  flock 9
                  if [[ ! -f $marker ]]; then
                    /run/wrappers/bin/mullvad-exclude umu-run winetricks ${lib.escapeShellArgs winetricks}
                    touch "$marker"
                  fi
                  flock -u 9
                  exec 9>&-
                fi
              ''}
              exec /run/wrappers/bin/mullvad-exclude umu-run "$launcher" "$@"
            '';
          };
          desktop = pkgs.makeDesktopItem (
            {
              name = command;
              inherit desktopName;
              exec = "${wrapper}/bin/${command} %U";
              categories = [ "Game" ];
            }
            // lib.optionalAttrs (startupWMClass != null) {
              extraConfig.StartupWMClass = startupWMClass;
            }
          );
        in
        pkgs.symlinkJoin {
          name = "${command}-${source.version}";
          paths = [
            wrapper
            desktop
          ];
        };

      # Official Windows OctoLauncher under UMU-Proton. Nix pins the bootstrap installer;
      # the prefix (launcher/client/addons/settings) stays writable for the self-updater.
      # Version/hash managed by nvfetcher (nvfetcher.toml [octowow]).
      octowow = mkUmuLauncher {
        id = "octowow";
        command = "octo-launcher";
        desktopName = "OctoLauncher";
        prefix = cfg.octowow.prefixPath;
        source = sources.octowow;
        launcherPath = "drive_c/users/steamuser/AppData/Local/Programs/OctoLauncher/OctoLauncher.exe";
        startupWMClass = "OctoLauncher";
      };

      # Official SWG Restoration installer under UMU-Proton. Nix pins the bootstrap
      # installer; the prefix stays writable for the self-updater.
      # Version/hash managed by nvfetcher (nvfetcher.toml [swgr]).
      swgr = mkUmuLauncher {
        id = "swgr";
        command = "swg-restoration";
        desktopName = "SWG Restoration";
        prefix = cfg.swgr.prefixPath;
        source = sources.swgr;
        launcherPath = "drive_c/SWG Restoration/SWG Restoration.exe";
        winetricks = [
          "win10"
          "hidewineexports=enable"
          "windowmanagerdecorated=n"
          "windowmanagermanaged=y"
          "d3dcompiler_43"
          "d3dx10"
          "d3dx9"
          "d3dx9_39"
          "dxvk"
          "xact"
          "xact_x64"
          "vcrun2022"
        ];
      };

      # Official TLOPO Windows installer under UMU-Proton. Nix pins the bootstrap
      # installer; the prefix stays writable for the launcher self-updater.
      # Version/hash managed by nvfetcher (nvfetcher.toml [tlopo]).
      tlopo = mkUmuLauncher {
        id = "tlopo";
        desktopName = "The Legend of Pirates Online";
        prefix = cfg.tlopo.prefixPath;
        source = sources.tlopo;
        launcherPath = "drive_c/Program Files/TLOPO/launcher.exe";
      };

      # Wrapper that excludes cloud-save games, rescues DRM-free/non-Steam games
      ludusaviBackupWrapper =
        pkgs.writers.writePython3Bin "ludusavi-backup-wrapper"
          {
            libraries = with pkgs.python3Packages; [ pyyaml ];
            flakeIgnore = [ "E501" ];
          }
          ''
            import os
            import sys
            import re
            import glob

            CONFIG_PATH = os.path.expanduser("~/.config/ludusavi/config.yaml")
            MANIFEST_PATH = os.path.expanduser("~/.config/ludusavi/manifest.yaml")
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


            def find_cloud_games(names):
                import yaml
                cloud_games = set()
                current = None
                in_cloud = False
                stores = {"epic", "gog", "origin", "steam", "uplay"}
                with open(MANIFEST_PATH) as manifest:
                    for line in manifest:
                        if line and not line[0].isspace():
                            header = line.rstrip()
                            if not header.endswith(":"):
                                current = None
                            else:
                                name = header[:-1]
                                if name.startswith('"'):
                                    name = yaml.safe_load(name)
                                current = name if name in names else None
                            in_cloud = False
                        elif current:
                            if line == "  cloud:\n":
                                in_cloud = True
                            elif in_cloud:
                                if not line.startswith("    "):
                                    in_cloud = False
                                else:
                                    store, _, value = line.strip().partition(":")
                                    if store in stores and value.strip() == "true":
                                        cloud_games.add(current)
                return cloud_games


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
                    name_to_cid[game_name] = None
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


            # Live-service games with server-side state — no local saves to back up
            force_exclude = {
                "Lethal Company", "MultiVersus", "Payday 3",
                "The Finals", "Webfishing", "Marvel Rivals",
                "Sea of Thieves",
            }

            # ── Main ──
            backup_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Games/Saves/ammars-pc")
            name_to_cid = build_compatdata_map(backup_path)

            # Ignoring a game only prevents backup; ignoring its compatdata path
            # prevents Ludusavi from scanning it during backup discovery.
            config = load_config()
            ignored_paths = set(config["backup"]["filter"].get("ignoredPaths", []))
            for game in force_exclude:
                if cid := name_to_cid.get(game):
                    ignored_paths.update(f"{lib}/compatdata/{cid}" for lib in STEAM_LIBS)
            config["backup"]["filter"]["ignoredPaths"] = sorted(ignored_paths)
            save_config(config)

            # Ludusavi's cloud filter intentionally keeps games with existing
            # backups. Read their cloud metadata directly instead of running two
            # full previews across the entire manifest.
            cloud_games = find_cloud_games(name_to_cid.keys())

            rescued = set()
            for game in cloud_games:
                cid = name_to_cid.get(game)
                if cid and not has_appmanifest(cid):
                    rescued.add(game)

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

        octowow = {
          enable = lib.mkEnableOption "OctoWoW official launcher via UMU-Proton";
          prefixPath = lib.mkOption {
            type = lib.types.str;
            default = "${config.xdg.dataHome}/octowow/prefix";
            description = "Writable Proton prefix for OctoLauncher";
          };
        };

        swgr = {
          enable = lib.mkEnableOption "SWG Restoration launcher via UMU-Proton";
          prefixPath = lib.mkOption {
            type = lib.types.str;
            default = "${config.xdg.dataHome}/swgr/prefix";
            description = "Writable Proton prefix for SWG Restoration";
          };
        };

        tlopo = {
          enable = lib.mkEnableOption "The Legend of Pirates Online launcher via UMU-Proton";
          prefixPath = lib.mkOption {
            type = lib.types.str;
            default = "${config.xdg.dataHome}/tlopo/prefix";
            description = "Writable Proton prefix for TLOPO";
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
          ++ lib.optionals cfg.octowow.enable [
            octowow
          ]
          ++ lib.optionals cfg.swgr.enable [
            swgr
          ]
          ++ lib.optionals cfg.tlopo.enable [
            tlopo
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
