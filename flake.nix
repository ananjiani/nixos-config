{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    sops-nix.url = "github:Mic92/sops-nix";
    xremap.url = "github:xremap/nix-flake";
    waybar.url = "github:alexays/waybar";
    nix-std.url = "github:chessai/nix-std";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    claude-code.url = "github:sadjow/claude-code-nix";
    whisper-dictation.url = "github:ananjiani/whisper-dictation";
    opencode = {
      url = "github:ananjiani/opencode-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager-unstable,
      nix-std,
      ...
    }@inputs:
    let
      # System configuration
      system = "x86_64-linux";
      inherit (nixpkgs-unstable) lib;
      std = nix-std.lib;

      # Package sets
      pkgs = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      pkgs-stable = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Special arguments passed to all configurations
      specialArgs = { inherit pkgs-stable; };
      extraSpecialArgs = { inherit inputs std pkgs-stable; };
    in
    {
      # Set nixPath for compatibility
      nix.nixPath = [ "nixpkgs=${nixpkgs-unstable}" ];

      # NixOS system configurations
      nixosConfigurations = {
        # Desktop system
        ammars-pc = lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/desktop/configuration.nix ];
        };

        # Work laptop
        work-laptop = lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/work-laptop/configuration.nix ];
        };

        # Surface Go tablet
        surface-go = lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/surface-go/configuration.nix ];
        };

        # Framework 13 laptop
        framework13 = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/framework13/configuration.nix
            inputs.nixos-hardware.nixosModules.framework-13-7040-amd
          ];
        };

        # ISO image for installation
        iso = lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/iso/configuration.nix ];
        };
      };

      # Home Manager configurations with automatic hostname detection
      homeConfigurations =
        let
          mkHomeConfig =
            hostPath:
            home-manager-unstable.lib.homeManagerConfiguration {
              inherit pkgs extraSpecialArgs;

              modules = [
                # Apply overlays
                {
                  nixpkgs.overlays = [
                    inputs.emacs-overlay.overlay
                    inputs.nix-vscode-extensions.overlays.default
                    inputs.claude-code.overlays.default
                  ];
                }

                # Load host-specific home configuration
                hostPath
              ];
            };
        in
        {
          # Automatic hostname detection: home-manager looks for $USER@$HOSTNAME then $USER
          "ammar@ammars-pc" = mkHomeConfig ./hosts/desktop/home.nix;
          "ammar@work-laptop" = mkHomeConfig ./hosts/work-laptop/home.nix;
          "ammar@framework13" = mkHomeConfig ./hosts/framework13/home.nix;
          "ammar@surface-go" = mkHomeConfig ./hosts/surface-go/home.nix;

          # Fallback configuration (if hostname doesn't match)
          "ammar" = mkHomeConfig ./hosts/default/home.nix;
        };

      # Pre-commit hooks configuration
      checks.${system}.pre-commit-check = inputs.git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          # First run formatters
          nixfmt-rfc-style.enable = true;

          # Then run linters/fixers
          deadnix = {
            enable = true;
            # Apply fixes automatically
            entry = "${pkgs.deadnix}/bin/deadnix --edit";
            pass_filenames = true;
          };
          statix = {
            enable = true;
            # Note: statix doesn't support auto-fixing well in pre-commit
            # Consider running `statix fix` manually when needed
          };

          # Security scanning
          ripsecrets.enable = true;

          # Custom vulnix hook for vulnerability scanning
          vulnix = {
            enable = true;
            name = "vulnix";
            description = "Scan for security vulnerabilities in Nix dependencies";
            entry = "${pkgs.vulnix}/bin/vulnix";
            pass_filenames = false;
            files = "flake\\.lock$";
          };

          # Git hygiene
          check-merge-conflicts.enable = true;
          check-added-large-files.enable = true;
          end-of-file-fixer.enable = true;
          trim-trailing-whitespace.enable = true;

          flake-checker.enable = true;
        };
      };

      # Development shell with pre-commit hooks
      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit-check) shellHook;
        buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;
      };
    };
}
