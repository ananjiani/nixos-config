# Dendritic OpenDeck Module
# Stream Deck controller software with declarative plugin/profile management
# Uses copy semantics for plugins (Wine prefix support) and seed-only-if-missing for profiles
_:

let
  # Package derivation using AppImage
  mkOpendeck =
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
      unwrapped = pkgs.appimageTools.wrapType2 {
        pname = "opendeck";
        inherit (sources.opendeck) version src;
        extraPkgs = _pkgs: with _pkgs; [
          wine
          winetricks
        ];
      };
    in
    # Wrap with environment variable to fix EGL/WebKitGTK issue on Wayland
    pkgs.symlinkJoin {
      name = "opendeck-${sources.opendeck.version}";
      paths = [ unwrapped ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/opendeck \
          --set WEBKIT_DISABLE_DMABUF_RENDERER 1
      '';
    };
in
{
  # NixOS Aspect - System level package + udev rules
  flake.aspects.opendeck.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.opendeck = {
        enable = lib.mkEnableOption "OpenDeck Stream Deck controller";
      };

      config = lib.mkIf config.opendeck.enable {
        environment.systemPackages = [ (mkOpendeck pkgs) ];

        # Use streamdeck-ui's udev rules (modern TAG+="uaccess" approach)
        # This grants device access to logged-in users without raw MODE="0666"
        services.udev.packages = [ pkgs.streamdeck-ui ];
      };
    };

  # Home Manager Aspect - Declarative plugin/profile management
  # Uses COPY semantics with "seed only if missing" for profiles
  flake.aspects.opendeck.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.opendeck;
      dataDir = "${config.xdg.dataHome}/opendeck";
    in
    {
      options.opendeck = {
        enable = lib.mkEnableOption "OpenDeck declarative configuration";

        plugins = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Human-readable plugin name";
                };
                uuid = lib.mkOption {
                  type = lib.types.str;
                  description = "Plugin UUID (directory name)";
                };
                src = lib.mkOption {
                  type = lib.types.either lib.types.path lib.types.package;
                  description = "Plugin source (extracted plugin directory)";
                };
              };
            }
          );
          default = [ ];
          description = "Plugins to install (copied, allowing Wine prefix creation)";
        };

        seedProfiles = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
          example = {
            "StreamDeckXL" = {
              "default" = {
                id = "default";
                keys = [ ];
                sliders = [ ];
              };
            };
          };
          description = ''
            Seed profiles (device -> profile-id -> JSON data).
            Only copied if the profile doesn't already exist.
            GUI changes persist across rebuilds.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Activation script: copy plugins and seed profiles
        home.activation.opendeckSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Create directories
          mkdir -p "${dataDir}/plugins"
          mkdir -p "${dataDir}/profiles"

          # Copy plugins (always update to latest declared version)
          ${lib.concatMapStringsSep "\n" (plugin: ''
            echo "Installing OpenDeck plugin: ${plugin.name}"
            rm -rf "${dataDir}/plugins/${plugin.uuid}"
            cp -r "${plugin.src}" "${dataDir}/plugins/${plugin.uuid}"
            chmod -R u+w "${dataDir}/plugins/${plugin.uuid}"
          '') cfg.plugins}

          # Seed profiles (only if missing - preserves user GUI edits)
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              device: profiles:
              ''mkdir -p "${dataDir}/profiles/${device}"''
              + "\n"
              + lib.concatStringsSep "\n" (
                lib.mapAttrsToList (profileId: profileData: ''
                  if [ ! -f "${dataDir}/profiles/${device}/${profileId}.json" ]; then
                    echo "Seeding OpenDeck profile: ${device}/${profileId}"
                    cat > "${dataDir}/profiles/${device}/${profileId}.json" << 'PROFILE_EOF'
          ${builtins.toJSON profileData}
          PROFILE_EOF
                  fi
                '') profiles
              )
            ) cfg.seedProfiles
          )}
        '';
      };
    };
}
