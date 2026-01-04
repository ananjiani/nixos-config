{
  pkgs,
  lib,
  ...
}:

let
  # Add npm packages you want installed globally here
  npmGlobalPackages = [
    # "vercel"
    # "netlify-cli"
    "happy-coder"
  ];
in
{
  home = {
    # npm global packages - install to ~/.npm-global instead of /usr
    sessionPath = [ "$HOME/.npm-global/bin" ];
    file.".npmrc".text = ''
      prefix=~/.npm-global
    '';

    # Declaratively install npm global packages
    activation.npmGlobalPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${pkgs.nodejs}/bin:$PATH"
      export npm_config_prefix="$HOME/.npm-global"
      NODE_MODULES="$HOME/.npm-global/lib/node_modules"

      # Desired packages
      desired=(${lib.escapeShellArgs npmGlobalPackages})

      # Install missing packages
      for pkg in "''${desired[@]}"; do
        if [ -n "$pkg" ] && ! [ -d "$NODE_MODULES/$pkg" ]; then
          run ${pkgs.nodejs}/bin/npm install -g "$pkg"
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
            run ${pkgs.nodejs}/bin/npm uninstall -g "$pkg"
          fi
        done
      fi
    '';

    packages = with pkgs; [
      # inputs.opencode.packages.${pkgs.system}.default
      nodejs # for npm global packages
      gh
      pgadmin4-desktopmode
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
}
