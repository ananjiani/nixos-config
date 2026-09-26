{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  cfg = config.devPrograms;
  herdrPkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./herdr/remote-file-paste.patch ];
  });
  reviewrPluginId = "persiyanov.reviewr";
  # persiyanov/herdr-reviewr v0.38.0
  reviewrPluginSrc = pkgs.fetchFromGitHub {
    owner = "persiyanov";
    repo = "herdr-reviewr";
    rev = "dca1fb88a56c0d6246a2e9004ecbe27fd11a4436";
    hash = "sha256-nHQlbENR4NQBKz2GTkYQqhr0JuulqFYSi7CjiIY9IhY=";
  };
  reviewrPluginArchive = pkgs.fetchurl {
    url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v0.38.0/herdr-reviewr-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-lr1qk35ZuJNFnXZxUsEUarhRbkqxRm4vdAFGAXNXWbQ=";
  };
  reviewrPluginRoot =
    pkgs.runCommand "herdr-reviewr-plugin"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        mkdir -p $out
        cp -a ${reviewrPluginSrc}/. $out/
        chmod -R u+w $out
        mkdir -p $out/bin
        tar -xzf ${reviewrPluginArchive} -C $out/bin
        chmod +x $out/bin/herdr-reviewr
      '';
in
{
  options.devPrograms.npmGlobalPackages = lib.mkOption {
    type = lib.types.nullOr (lib.types.listOf lib.types.str);
    default = [ "happy-coder" ];
    description = ''
      npm packages installed globally under ~/.npm-global on each home
      activation when non-null (best-effort install + uninstall cleanup).
      null fully disables management — no install and no uninstall — so
      existing employer-VM globals are left alone (Denethor). [] would still
      uninstall everything not in the list; prefer null for isolation.
    '';
  };

  config = {
    xdg.configFile."herdr/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/modules/home/dev/herdr/config.toml";

    home = {
      # After other sessionPath entries (e.g. ~/.local/bin from claude-code)
      # so merge order stays deterministic across hosts.
      sessionPath = lib.mkAfter [ "$HOME/.npm-global/bin" ];
      file.".npmrc".text = ''
        prefix=~/.npm-global
        loglevel=error
      '';

      # Declaratively install npm global packages. Best-effort: network/npm
      # failure must not abort HM activation. Skipped entirely when null.
      activation = {
        npmGlobalPackages = lib.mkIf (cfg.npmGlobalPackages != null) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            export PATH="${pkgs.nodejs}/bin:$PATH"
            export npm_config_prefix="$HOME/.npm-global"
            NODE_MODULES="$HOME/.npm-global/lib/node_modules"

            # Desired packages
            desired=(${
              lib.escapeShellArgs (if cfg.npmGlobalPackages == null then [ ] else cfg.npmGlobalPackages)
            })

            # Install missing packages
            for pkg in "''${desired[@]}"; do
              if [ -n "$pkg" ] && ! [ -d "$NODE_MODULES/$pkg" ]; then
                run ${pkgs.nodejs}/bin/npm install -g "$pkg" \
                  || echo "npm: failed to install global package '$pkg' (network/npm error?), skipping" >&2
              fi
            done

            # Remove packages not in the list
            if [ -d "$NODE_MODULES" ]; then
              for installed in "$NODE_MODULES"/*; do
                [ -d "$installed" ] || continue
                pkg=$(basename "$installed")

                # Skip npm internal packages
                case "$pkg" in
                  .package-lock.json|.bin) continue ;;
                esac

                # Check if package is in desired list
                found=0
                for want in "''${desired[@]}"; do
                  if [ "$pkg" = "$want" ]; then
                    found=1
                    break
                  fi
                done

                if [ "$found" = 0 ]; then
                  run ${pkgs.nodejs}/bin/npm uninstall -g "$pkg" \
                    || echo "npm: failed to uninstall global package '$pkg', skipping" >&2
                fi
              done
            fi
          ''
        );

        # Link Nix-pinned herdr-reviewr when plugin_root drifts. herdr plugin
        # link skips [[build]], so activation never downloads GitHub assets.
        installReviewrPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          export PATH="${
            lib.makeBinPath [
              herdrPkg
              pkgs.jq
              pkgs.coreutils
            ]
          }:$PATH"
          plugins_json="$HOME/.config/herdr/plugins.json"
          want_root="${reviewrPluginRoot}"
          have_root=""
          if [ -f "$plugins_json" ]; then
            have_root="$(jq -r --arg id "${reviewrPluginId}" \
              '.[] | select(.plugin_id == $id) | .plugin_root // empty' \
              "$plugins_json" 2>/dev/null || true)"
          fi
          if [ "$have_root" != "$want_root" ]; then
            if [ -n "$have_root" ]; then
              kind="$(jq -r --arg id "${reviewrPluginId}" \
                '.[] | select(.plugin_id == $id) | .source.kind // empty' \
                "$plugins_json" 2>/dev/null || true)"
              case "$kind" in
                github)
                  run herdr plugin uninstall "${reviewrPluginId}" 2>/dev/null || true
                  ;;
                *)
                  if ! run herdr plugin unlink "${reviewrPluginId}" 2>/dev/null; then
                    run herdr plugin uninstall "${reviewrPluginId}" 2>/dev/null || true
                  fi
                  ;;
              esac
            fi
            run herdr plugin link "$want_root"
          fi
          if herdr status server >/dev/null 2>&1; then
            run herdr server reload-config
          fi
        '';
      };

      packages = with pkgs; [
        # inputs.opencode.packages.${pkgs.system}.default
        nodejs # for npm global packages
        gh
        herdrPkg
        # inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs # Temporarily disabled - hash mismatch
      ];
    };

    programs = {
      opencode.enable = true;
      jujutsu = {
        enable = true;
        settings = {
          user = {
            email = "ammar.nanjiani@gmail.com";
            name = "Ammar Nanjiani";
          };
        };
      };
    };
  };
}
