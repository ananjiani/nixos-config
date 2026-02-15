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

      # Build the list of secret file paths to pass as env vars to the Python script
      secretEnvs = lib.concatStringsSep "\n" (
        lib.optional (
          cfg.secrets.traktClientId != null
        ) ''export TRAKT_CLIENT_FILE="${cfg.secrets.traktClientId}"''
        ++ lib.optional (
          cfg.secrets.traktClientSecret != null
        ) ''export TRAKT_SECRET_FILE="${cfg.secrets.traktClientSecret}"''
      );

      injectSecrets = pkgs.writeShellScript "kodi-inject-secrets" ''
        set -euo pipefail

        mkdir -p "${addonDataDir}"

        ${secretEnvs}
        export SETTINGS_FILE="${addonDataDir}/settings.xml"

        ${pkgs.python3}/bin/python3 <<'PYTHON'
        import os
        import xml.etree.ElementTree as ET

        settings_file = os.environ["SETTINGS_FILE"]

        # Load existing settings or create new root
        if os.path.isfile(settings_file):
            tree = ET.parse(settings_file)
            root = tree.getroot()
        else:
            root = ET.fromstring('<settings version="2"></settings>')
            tree = ET.ElementTree(root)

        def upsert(setting_id, value):
            el = root.find(f".//setting[@id='{setting_id}']")
            if el is None:
                el = ET.SubElement(root, "setting", id=setting_id)
            el.text = value

        # Read secrets from SOPS-decrypted files and merge into settings
        trakt_client_file = os.environ.get("TRAKT_CLIENT_FILE")
        if trakt_client_file:
            upsert("trakt_enabled", "true")
            upsert("trakt_client", open(trakt_client_file).read().strip())

        trakt_secret_file = os.environ.get("TRAKT_SECRET_FILE")
        if trakt_secret_file:
            upsert("trakt_secret", open(trakt_secret_file).read().strip())

        tree.write(settings_file, xml_declaration=False)
        os.chmod(settings_file, 0o600)
        PYTHON
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
