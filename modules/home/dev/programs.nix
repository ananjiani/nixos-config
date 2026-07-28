{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  cfg = config.devPrograms;
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
      activation = lib.mkIf (cfg.npmGlobalPackages != null) {
        npmGlobalPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
        '';
      };

      packages = with pkgs; [
        # inputs.opencode.packages.${pkgs.system}.default
        nodejs # for npm global packages
        gh
        inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
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
