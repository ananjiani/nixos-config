{
  description = "OpenCode - AI coding agent built for the terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: 
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          
          opencode-node-modules-hash = {
            "aarch64-darwin" = "sha256-+eXXWskZg0CIY12+Ee4Y3uwpB5I92grDiZ600Whzx/I=";
            "aarch64-linux" = "sha256-rxLPrYAIiKDh6de/GACPfcYXY7nIskqAu1Xi12y5DpU=";
            "x86_64-darwin" = "sha256-LOz7N6gMRaZLPks+y5fDIMOuUCXTWpHIss1v0LHPnqw=";
            "x86_64-linux" = "sha256-B/nTDMoADK+okDOROCCTF51GJALVlOMilEGWmLqmixA=";
          };
          
          bun-target = {
            "aarch64-darwin" = "bun-darwin-arm64";
            "aarch64-linux" = "bun-linux-arm64";
            "x86_64-darwin" = "bun-darwin-x64";
            "x86_64-linux" = "bun-linux-x64";
          };
          
          opencode = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
            pname = "opencode";
            version = "0.3.5";
            
            src = pkgs.fetchFromGitHub {
              owner = "sst";
              repo = "opencode";
              rev = "v${finalAttrs.version}";
              hash = "sha256-FX4dlDOEsKBTucZhzAWI2fUqBffc+UWXW00YpmO2EUs=";
            };
            
            tui = pkgs.buildGoModule {
              pname = "opencode-tui";
              inherit (finalAttrs) version;
              src = "${finalAttrs.src}/packages/tui";
              
              vendorHash = "sha256-TkY4wVCaZ9JjwPE/K4ThCnxakcQwFmSVgUSYlWU4yiw=";
              
              subPackages = [ "cmd/opencode" ];
              
              env.CGO_ENABLED = 0;
              
              ldflags = [
                "-s"
                "-X=main.Version=${finalAttrs.version}"
              ];
              
              installPhase = ''
                runHook preInstall
                
                install -Dm755 $GOPATH/bin/opencode $out/bin/tui
                
                runHook postInstall
              '';
            };
            
            node_modules = pkgs.stdenvNoCC.mkDerivation {
              pname = "opencode-node_modules";
              inherit (finalAttrs) version src;
              
              impureEnvVars = pkgs.lib.fetchers.proxyImpureEnvVars ++ [
                "GIT_PROXY_COMMAND"
                "SOCKS_SERVER"
              ];
              
              nativeBuildInputs = [
                pkgs.bun
                pkgs.writableTmpDirAsHomeHook
              ];
              
              dontConfigure = true;
              
              buildPhase = ''
                runHook preBuild
                
                 export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
                
                 bun install \
                   --filter=opencode \
                   --force \
                   --frozen-lockfile \
                   --no-progress
                
                runHook postBuild
              '';
              
              installPhase = ''
                runHook preInstall
                
                mkdir -p $out/node_modules
                cp -R ./node_modules $out
                
                runHook postInstall
              '';
              
              # Required else we get errors that our fixed-output derivation references store paths
              dontFixup = true;
              
              outputHash = opencode-node-modules-hash.${system};
              outputHashAlgo = "sha256";
              outputHashMode = "recursive";
            };
            
            models-dev-data = pkgs.fetchurl {
              url = "https://models.dev/api.json";
              sha256 = "sha256-AMJyDjqOKTGGRYLN5rEUQraJ+5E+9YULUH1gWph0s0o=";
            };
            
            nativeBuildInputs = [ pkgs.bun ];
            
            patches = [ ./fix-models-macro.patch ];
            
            configurePhase = ''
              runHook preConfigure
              
              cp -R ${finalAttrs.node_modules}/node_modules .
              
              runHook postConfigure
            '';
            
            buildPhase = ''
              runHook preBuild
              
              export MODELS_JSON="$(cat ${finalAttrs.models-dev-data})"
              bun build \
                --define OPENCODE_VERSION="'${finalAttrs.version}'" \
                --compile \
                --minify \
                --target=${bun-target.${system}} \
                --outfile=opencode \
                ./packages/opencode/src/index.ts \
                ${finalAttrs.tui}/bin/tui
              
              runHook postBuild
            '';
            
            dontStrip = true;
            
            installPhase = ''
              runHook preInstall
              
              mkdir -p $out/bin
              install -Dm755 opencode $out/bin/opencode
              
              runHook postInstall
            '';
            
            passthru = {
              tests.version = pkgs.testers.testVersion {
                package = finalAttrs.finalPackage;
                command = "HOME=$(mktemp -d) opencode --version";
                inherit (finalAttrs) version;
              };
            };
            
            meta = with pkgs.lib; {
              description = "AI coding agent built for the terminal";
              longDescription = ''
                OpenCode is a terminal-based agent that can build anything.
                It combines a TypeScript/JavaScript core with a Go-based TUI
                to provide an interactive AI coding experience.
              '';
              homepage = "https://github.com/sst/opencode";
              license = licenses.mit;
              platforms = platforms.unix;
              maintainers = with maintainers; [ ];
              mainProgram = "opencode";
            };
          });
        in
        {
          default = opencode;
          opencode = opencode;
        }
      );
    };
}