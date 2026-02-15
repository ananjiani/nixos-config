# Dendritic Kodi Module
# Aspect-oriented configuration for Kodi HTPC with debrid streaming.
# NixOS aspect: SOPS secret injection into Jacktook addon settings (Trakt)
# Home Manager aspect: advancedsettings.xml via programs.kodi.settings
_:

let
  jacktookAddon = "plugin.video.jacktook";
in
{
  # NixOS aspect — SOPS secret injection into Kodi addon settings
  # Debrid (TorBox) is handled by Comet Stremio addon, so only Trakt secrets are injected.
  flake.aspects.kodi.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.kodi;
      hasSecrets = cfg.secrets.traktClientId != null;
      kodiHome = config.users.users.${cfg.user}.home;
      addonDataDir = "${kodiHome}/.kodi/userdata/addon_data/${jacktookAddon}";

      injectSecrets = pkgs.writeShellScript "kodi-inject-secrets" ''
        set -euo pipefail

        SETTINGS_DIR="${addonDataDir}"
        SETTINGS_FILE="$SETTINGS_DIR/settings.xml"

        mkdir -p "$SETTINGS_DIR"

        # Start building settings XML
        {
          echo '<settings version="2">'

          ${lib.optionalString (cfg.secrets.traktClientId != null) ''
            TRAKT_CLIENT=$(cat "${cfg.secrets.traktClientId}")
            echo "  <setting id=\"trakt_enabled\">true</setting>"
            echo "  <setting id=\"trakt_client\">$TRAKT_CLIENT</setting>"
          ''}

          ${lib.optionalString (cfg.secrets.traktClientSecret != null) ''
            TRAKT_SECRET=$(cat "${cfg.secrets.traktClientSecret}")
            echo "  <setting id=\"trakt_secret\">$TRAKT_SECRET</setting>"
          ''}

          echo '</settings>'
        } > "$SETTINGS_FILE"

        chmod 600 "$SETTINGS_FILE"
      '';
    in
    {
      options.kodi = {
        user = lib.mkOption {
          type = lib.types.str;
          default = "kodi";
          description = "Username of the Kodi service user (must match modules.htpc.kodiUser)";
        };

        secrets = {
          traktClientId = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to SOPS-decrypted Trakt client ID file";
          };

          traktClientSecret = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to SOPS-decrypted Trakt client secret file";
          };
        };
      };

      config = lib.mkIf hasSecrets {
        systemd.services.kodi-addon-settings = {
          description = "Inject SOPS secrets into Kodi addon settings";
          wantedBy = [ "multi-user.target" ];
          before = [ "greetd.service" ];
          after = [ "sops-nix.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = cfg.user;
            ExecStart = injectSecrets;
          };
        };
      };
    };

  # Home Manager aspect — advancedsettings.xml for debrid streaming
  flake.aspects.kodi.homeManager =
    {
      lib,
      config,
      ...
    }:
    {
      options.kodi = {
        enable = lib.mkEnableOption "Kodi declarative configuration";
      };

      config = lib.mkIf config.kodi.enable {
        programs.kodi = {
          enable = true;
          # advancedsettings.xml — buffer tuning for debrid streaming
          settings = {
            cache = {
              memorysize = "52428800"; # 50MB read buffer
              readfactor = "20"; # Read ahead at 20x playback speed
            };
          };
        };
      };
    };
}
