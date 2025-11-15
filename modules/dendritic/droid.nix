# Dendritic Droid Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
{ inputs, ... }:

let
  # Source information for droid and ripgrep
  sources = {
    droid = {
      version = "0.26.0";
      x64 = {
        url = "https://downloads.factory.ai/factory-cli/releases/0.26.0/linux/x64/droid";
        sha256 = "sha256-DtqZylT+6IMs4uVw/qHqkJAXauEWZac+DTVThSZedPc=";
      };
      x64-baseline = {
        url = "https://downloads.factory.ai/factory-cli/releases/0.26.0/linux/x64-baseline/droid";
        sha256 = "sha256-FAKEHASH"; # TODO: Add if needed for systems without AVX2
      };
      arm64 = {
        url = "https://downloads.factory.ai/factory-cli/releases/0.26.0/linux/arm64/droid";
        sha256 = "sha256-FAKEHASH"; # TODO: Add if needed for ARM systems
      };
    };
    ripgrep = {
      x64 = {
        url = "https://downloads.factory.ai/ripgrep/linux/x64/rg";
        sha256 = "sha256-viR2yXY0K5IWYRtKhMG8LsZIjsXHkeoBmhMnJ2RO8Zw=";
      };
      arm64 = {
        url = "https://downloads.factory.ai/ripgrep/linux/arm64/rg";
        sha256 = "sha256-FAKEHASH"; # TODO: Add if needed for ARM systems
      };
    };
  };

  # Detect architecture and select appropriate source
  getArchSources =
    pkgs:
    let
      arch = pkgs.stdenv.hostPlatform.system;
    in
    if arch == "x86_64-linux" then
      {
        droid = sources.droid.x64;
        ripgrep = sources.ripgrep.x64;
      }
    else if arch == "aarch64-linux" then
      {
        droid = sources.droid.arm64;
        ripgrep = sources.ripgrep.arm64;
      }
    else
      throw "Unsupported architecture: ${arch}";

  # Build raw droid binary
  mkDroidBinary =
    pkgs:
    let
      archSources = getArchSources pkgs;
    in
    pkgs.stdenv.mkDerivation {
      pname = "droid";
      inherit (sources.droid) version;

      src = pkgs.fetchurl {
        inherit (archSources.droid) url sha256;
      };

      nativeBuildInputs = with pkgs; [ autoPatchelfHook ];

      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
        glibc
      ];

      dontUnpack = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cp $src $out/bin/droid
        chmod +x $out/bin/droid

        runHook postInstall
      '';

      meta = with pkgs.lib; {
        description = "Factory.ai development agent CLI";
        homepage = "https://factory.ai";
        license = licenses.unfree;
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        mainProgram = "droid";
      };
    };

  # Build Factory's custom ripgrep binary
  mkRipgrep =
    pkgs:
    let
      archSources = getArchSources pkgs;
    in
    pkgs.stdenv.mkDerivation {
      pname = "factory-ripgrep";
      version = "custom";

      src = pkgs.fetchurl {
        inherit (archSources.ripgrep) url sha256;
      };

      nativeBuildInputs = with pkgs; [ autoPatchelfHook ];

      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
        glibc
      ];

      dontUnpack = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cp $src $out/bin/rg
        chmod +x $out/bin/rg

        runHook postInstall
      '';

      meta = with pkgs.lib; {
        description = "Factory.ai's custom ripgrep binary for droid";
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      };
    };

  # Create wrapped droid package with ripgrep dependency
  mkDroid =
    pkgs:
    let
      droidBinary = mkDroidBinary pkgs;
      ripgrep = mkRipgrep pkgs;
    in
    inputs.wrappers.lib.wrapPackage {
      inherit pkgs;
      package = droidBinary;

      # Add ripgrep to PATH so droid can find it
      runtimeInputs = [ ripgrep ];

      # Droid may expect ~/.factory/bin/rg to exist
      # Create it on first run if needed
      preHook = ''
        # Create ~/.factory/bin directory if it doesn't exist
        if [ ! -d "$HOME/.factory/bin" ]; then
          mkdir -p "$HOME/.factory/bin"
        fi

        # Create symlink to ripgrep if it doesn't exist or is broken
        if [ ! -e "$HOME/.factory/bin/rg" ]; then
          ln -sf ${ripgrep}/bin/rg "$HOME/.factory/bin/rg"
        fi
      '';
    };
in
{
  # Home Manager configuration (user-level droid CLI)
  flake.aspects.droid.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.droid = {
        enable = lib.mkEnableOption "Factory.ai droid CLI";

        package = lib.mkOption {
          type = lib.types.package;
          default = mkDroid pkgs;
          description = ''
            The droid package to use.

            This is a wrapped version that includes ripgrep and handles
            the ~/.factory/bin directory setup automatically.

            You can override this with a custom package if needed.
          '';
        };
      };

      config = lib.mkIf config.droid.enable {
        home.packages = [ config.droid.package ];

        # Optional: Add shell completions or other integrations here
        # programs.bash.initExtra = ''
        #   # Droid shell integration if available
        # '';
      };
    };

  # Future: NixOS system-level configuration
  # Uncomment and expand when you need system-level droid functionality
  # flake.aspects.droid.nixos = { pkgs, lib, config, ... }: {
  #   options.services.droid = {
  #     # System-level droid services if needed
  #   };
  #   config = {
  #     # System-level configuration
  #   };
  # };

  # Future: macOS support via nix-darwin
  # Uncomment when you need macOS droid support
  # flake.aspects.droid.darwin = { pkgs, lib, config, ... }: {
  #   # macOS-specific droid configuration
  # };
}
