# Dendritic MoonDeck Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
_:

let
  # Package derivation using AppImage
  mkMoondeckBuddy =
    pkgs:
    let
      sources = import ../../_sources/generated.nix {
        inherit (pkgs)
          fetchurl
          fetchgit
          fetchFromGitHub
          dockerTools
          ;
      };
    in
    pkgs.appimageTools.wrapType2 {
      pname = "moondeck-buddy";
      inherit (sources.moondeck-buddy) version src;
      extraPkgs = _pkgs: [ ];
    };
in
{
  # NixOS configuration (system-level package and Sunshine integration)
  flake.aspects.moondeck.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.moondeck = {
        enable = lib.mkEnableOption "MoonDeck Buddy system-level package";

        sunshine = {
          enable = lib.mkEnableOption "Configure MoonDeckStream in Sunshine apps";

          appName = lib.mkOption {
            type = lib.types.str;
            default = "MoonDeckStream";
            description = "Application name shown in Moonlight";
          };
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall port for MoonDeck Buddy (59999)";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 59999;
          description = "Port for MoonDeck Buddy";
        };
      };

      config = lib.mkIf config.moondeck.enable {
        # Install package system-wide
        environment.systemPackages = [ (mkMoondeckBuddy pkgs) ];

        # Open firewall for MoonDeck Buddy
        networking.firewall.allowedTCPPorts = lib.mkIf config.moondeck.openFirewall [ config.moondeck.port ];

        # Configure Sunshine to include MoonDeckStream
        services.sunshine.applications = lib.mkIf config.moondeck.sunshine.enable {
          apps = [
            {
              name = config.moondeck.sunshine.appName;
              cmd = "${mkMoondeckBuddy pkgs}/bin/moondeck-buddy --exec MoonDeckStream";
            }
          ];
        };
      };
    };

  # Home Manager configuration (user-level service and settings)
  flake.aspects.moondeck.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.moondeck = {
        enable = lib.mkEnableOption "MoonDeck Buddy for Steam Deck game streaming";

        autostart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-start MoonDeck Buddy via systemd user service";
        };

        settings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
            options = {
              port = lib.mkOption {
                type = lib.types.port;
                default = 59999;
                description = "Communication port for MoonDeck Buddy";
              };

              loggingrules = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Logging rules (e.g., 'buddy.*.debug=true' for debug logging)";
              };

              preferhibernation = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Use hibernation instead of suspend";
              };

              closesteambeforesleep = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Automatically close Steam before sleep/hibernation";
              };

              sslprotocol = lib.mkOption {
                type = lib.types.str;
                default = "SecureProtocols";
                description = "SSL/TLS protocol version (SecureProtocols, TlsV1_2, TlsV1_3, etc.)";
              };

              macaddressoverride = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Manual MAC address override";
              };

              steamexecoverride = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Custom Steam executable path";
              };

              sunshineappsfilepath = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Path to Sunshine's apps.json file";
              };
            };
          };
          default = { };
          description = "MoonDeck Buddy settings (written to ~/.config/moondeckbuddy/settings.json)";
        };
      };

      config = lib.mkIf config.moondeck.enable {
        # Note: Package is installed system-wide via NixOS aspect
        # settings.json is managed by the app itself at ~/.config/moondeckbuddy/settings.json
        # The app needs write access to update settings, so we don't use declarative config here

        # Systemd user service (runs in graphical session)
        systemd.user.services.moondeckbuddy = lib.mkIf config.moondeck.autostart {
          Unit = {
            Description = "MoonDeck Buddy";
            Documentation = "https://github.com/FrogTheFrog/moondeck-buddy/wiki";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };

          Service = {
            Type = "simple";
            ExecStart = "${mkMoondeckBuddy pkgs}/bin/moondeck-buddy";
            Restart = "on-failure";
            RestartSec = "5s";
          };

          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
    };
}
