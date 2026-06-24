# Dendritic Crypto Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
_:

let
  # ponytail: cakewallet is MANUALLY pinned, deliberately NOT in nvfetcher.toml.
  # This is a crypto wallet — auto-bumping money-handling software via weekly CI
  # with automerge is a risk profile nobody should take. Bump deliberately after
  # reading release notes, and re-check the asset filename: upstream's tooling is
  # flaky (v6.2.1 shipped its Linux tarball mislabeled as v6.2.0). We pin v6.2.0
  # because it's the last correctly-named release AND is literally the binary
  # shipped under v6.2.1 anyway. If you re-add to nvfetcher, set automerge:false.
  sources = {
    cakewallet = {
      version = "v6.2.0";
      url = "https://github.com/cake-tech/cake_wallet/releases/download/v6.2.0/Cake_Wallet_v6.2.0_Linux.tar.xz";
      sha256 = "sha256-r/cAC5vK8qfnY27HvPRmfxbWsfWzola5+yVahBSZyoQ=";
    };
  };

  # Package derivation (shared across all configuration classes)
  mkCakewallet =
    pkgs:
    pkgs.stdenv.mkDerivation {
      pname = "cakewallet";
      inherit (sources.cakewallet) version;

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
  flake.aspects.crypto.homeManager =
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
