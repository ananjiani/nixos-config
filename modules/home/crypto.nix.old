{ pkgs, lib, config, ... }:

let
  # Source information (updated by nvfetcher via CI)
  sources = {
    cakewallet = {
      version = "v5.5.2";
      url = "https://github.com/cake-tech/cake_wallet/releases/download/v5.5.2/Cake_Wallet_v5.5.2_Linux.tar.xz";
      sha256 = "sha256-86G4t4EfZzAFxhCAGmcjGnp4A0N/ZpR71LKkKk+qZUc=";
    };
  };
  
  # Cakewallet package derivation
  cakewallet = pkgs.stdenv.mkDerivation {
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
        --prefix LD_LIBRARY_PATH : "$out/opt/cakewallet/lib:${lib.makeLibraryPath (with pkgs; [
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
        ])}" \
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
    
    meta = with lib; {
      description = "Cake Wallet - Open-source cryptocurrency wallet";
      homepage = "https://cakewallet.com/";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "cake-wallet";
    };
  };

in {
  options.crypto = {
    enable = lib.mkEnableOption "crypto applications";
    
    cakewallet = {
      enable = lib.mkEnableOption "Cake Wallet";
    };
  };
  
  config = lib.mkIf config.crypto.enable {
    home.packages = lib.optionals config.crypto.cakewallet.enable [ 
      cakewallet
    ];
  };
}