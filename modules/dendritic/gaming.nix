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
      };

      config = lib.mkIf cfg.enable {
        home.sessionVariables = {
          DXVK_HDR = "1";
        };

        home.packages = with pkgs; [
          gpu-screen-recorder
          gpu-screen-recorder-gtk
          wine-wayland
          protontricks
          heroic
        ];

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
