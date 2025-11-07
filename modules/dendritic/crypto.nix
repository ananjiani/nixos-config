# Dendritic Crypto Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
{ inputs, ... }:

let
  # Source information (updated by nvfetcher via CI)
  sources = {
    cakewallet = {
      version = "v5.5.2";
      url = "https://github.com/cake-tech/cake_wallet/releases/download/v5.5.2/Cake_Wallet_v5.5.2_Linux.tar.xz";
      sha256 = "sha256-86G4t4EfZzAFxhCAGmcjGnp4A0N/ZpR71LKkKk+qZUc=";
    };
  };

  # Package derivation (shared across all configuration classes)
  mkCakewallet =
    pkgs:
    pkgs.stdenv.mkDerivation {
      pname = "cakewallet";
      version = sources.cakewallet.version;

      src = pkgs.fetchurl {
        inherit (sources.cakewallet) url sha256;
      };

      nativeBuildInputs = with pkgs; [
        makeWrapper
        autoPatchelfHook
      ];

      buildInputs = with pkgs; [
        # System dependencies for Flutter/GTK app
        gtk3
        glib
        cairo
        pango
        harfbuzz
        gdk-pixbuf
        atk
        xorg.libX11
        xorg.libXcursor
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXi
        xorg.libXext
        xorg.libXfixes
        libGL
        libepoxy
        # Crypto dependencies
        openssl
        sqlite
        # Missing dependencies found by autoPatchelfHook
        libgcrypt
        lz4
        libgpg-error
      ];

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        
        # Find the extracted directory (it has version in name)
        CAKE_DIR=$(find . -maxdepth 1 -type d -name "Cake_Wallet_*" | head -n1)
        
        # Install application files
        mkdir -p $out/opt/cakewallet
        cp -r "$CAKE_DIR"/* $out/opt/cakewallet/
        
        # Make binary executable
        chmod +x $out/opt/cakewallet/cake_wallet
        
        # Create wrapper script
        mkdir -p $out/bin
        makeWrapper $out/opt/cakewallet/cake_wallet $out/bin/cake-wallet \
          --prefix LD_LIBRARY_PATH : "$out/opt/cakewallet/lib:${
            pkgs.lib.makeLibraryPath (
              with pkgs;
              [
                gtk3
                glib
                cairo
                pango
                harfbuzz
                gdk-pixbuf
                atk
                xorg.libX11
                xorg.libXcursor
                xorg.libXinerama
                xorg.libXrandr
                xorg.libXi
                xorg.libXext
                xorg.libXfixes
                libGL
                libepoxy
                openssl
                sqlite
                libgcrypt
                lz4
                libgpg-error
              ]
            )
          }" \
          --set GDK_BACKEND x11
        
        # Create desktop entry
        mkdir -p $out/share/applications
        cat > $out/share/applications/cake-wallet.desktop <<EOF
        [Desktop Entry]
        Name=Cake Wallet
        Comment=Secure cryptocurrency wallet
        Exec=$out/bin/cake-wallet
        Icon=cake-wallet
        Terminal=false
        Type=Application
        Categories=Office;Finance;
        EOF
        
        # Extract and install icon if available
        mkdir -p $out/share/icons/hicolor/256x256/apps
        if [ -f "$out/opt/cakewallet/data/flutter_assets/assets/images/app_logo.png" ]; then
          cp "$out/opt/cakewallet/data/flutter_assets/assets/images/app_logo.png" \
             $out/share/icons/hicolor/256x256/apps/cake-wallet.png
        fi
        
        runHook postInstall
      '';

      meta = with pkgs.lib; {
        description = "Cake Wallet - Open-source cryptocurrency wallet";
        homepage = "https://cakewallet.com/";
        license = licenses.mit;
        platforms = platforms.linux;
        mainProgram = "cake-wallet";
      };
    };
in
{
  # Home Manager configuration (user-level crypto applications)
  flake.modules.homeManager.crypto =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.crypto = {
        enable = lib.mkEnableOption "crypto applications";

        cakewallet = {
          enable = lib.mkEnableOption "Cake Wallet";
        };
      };

      config = lib.mkIf config.crypto.enable {
        home.packages = lib.optionals config.crypto.cakewallet.enable [ (mkCakewallet pkgs) ];
      };
    };

  # Home Manager configuration (user-level email applications)
  flake.modules.homeManager.email =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.email = {
        enable = lib.mkEnableOption "email applications and services";

        thunderbird = {
          enable = lib.mkEnableOption "Mozilla Thunderbird email client";
        };

        protonBridge = {
          enable = lib.mkEnableOption "Proton Mail Bridge";
          
          autostart = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Auto-start Proton Mail Bridge on login via systemd user service";
          };
        };

        # Future: Add support for other email clients
        # mu4e = {
        #   enable = lib.mkEnableOption "mu4e email client for Emacs";
        # };
        # aerc = {
        #   enable = lib.mkEnableOption "aerc terminal email client";
        # };
      };

      config = lib.mkIf config.email.enable (
        lib.mkMerge [
          # Thunderbird configuration
          (lib.mkIf config.email.thunderbird.enable {
            home.packages = [ pkgs.thunderbird ];
          })

          # Proton Mail Bridge configuration
          (lib.mkIf config.email.protonBridge.enable {
            home.packages = [ pkgs.protonmail-bridge ];

            # Optional: Auto-start Proton Mail Bridge via systemd user service
            systemd.user.services.protonmail-bridge = lib.mkIf config.email.protonBridge.autostart {
              Unit = {
                Description = "Proton Mail Bridge";
                After = [ "graphical-session.target" ];
              };

              Service = {
                Type = "simple";
                ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
                Restart = "on-failure";
                RestartSec = "5s";
                
                # Environment variables for consistent runtime
                Environment = [
                  "PATH=${pkgs.lib.makeBinPath [ pkgs.gnome-keyring ]}"
                ];
              };

              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };
          })
        ]
      );
    };

  # Future: NixOS system-level crypto services
  # Uncomment and expand when you need system-level crypto functionality
  # flake.modules.nixos.crypto = { pkgs, lib, config, ... }: {
  #   options.services.crypto = {
  #     # System-level crypto services (node runners, daemons, etc.)
  #   };
  #   config = {
  #     # System-level configuration
  #   };
  # };

  # Future: macOS support via nix-darwin
  # Uncomment when you need macOS crypto support
  # flake.modules.darwin.crypto = { pkgs, lib, config, ... }: {
  #   # macOS-specific crypto tools and services
  # };
}
