{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
      url = "github:k3d3/claude-desktop-linux-flake/276188d7200d2840d75729524b4950eadcfcdd7d";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    claude-code.url = "github:sadjow/claude-code-nix";
    whisper-dictation.url = "github:ananjiani/whisper-dictation";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nvfetcher = {
      url = "github:berberman/nvfetcher";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-unstable";
    };
    import-tree.url = "github:vic/import-tree";
    flake-aspects.url = "github:vic/flake-aspects";
    thunderbird-user-js = {
      url = "github:HorlogeSkynet/thunderbird-user.js";
      flake = false;
    };
    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    play-nix = {
      url = "github:TophC7/play.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.chaotic.follows = "chaotic";
    };
    nixos-avf = {
      url = "github:nix-community/nixos-avf";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    attic = {
      url = "github:zhaofengli/attic";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    buildbot-nix = {
      url = "github:nix-community/buildbot-nix";
    };
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager-unstable,
      nix-std,
      flake-parts,
      deploy-rs,
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
      specialArgs = { inherit inputs pkgs-stable; };
      extraSpecialArgs = { inherit inputs std pkgs-stable; };

      # Dendritic modules using flake-parts with import-tree and flake-aspects
      dendriticFlake = flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [
          system
          "aarch64-linux"
        ];
        imports = [
          inputs.flake-aspects.flakeModule
          (inputs.import-tree ./modules/dendritic)
        ];
      };
    in
    {
      # Expose dendritic modules for consumption
      modules = dendriticFlake.modules or { };
      # Set nixPath for compatibility
      nix.nixPath = [ "nixpkgs=${nixpkgs-unstable}" ];

      # NixOS system configurations
      nixosConfigurations = {
        # Desktop system
        ammars-pc = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/desktop/configuration.nix
            inputs.sops-nix.nixosModules.sops
            # Import dendritic moondeck NixOS module
            (if self.modules ? nixos && self.modules.nixos ? moondeck then self.modules.nixos.moondeck else { })
            # Import dendritic opendeck NixOS module
            (if self.modules ? nixos && self.modules.nixos ? opendeck then self.modules.nixos.opendeck else { })
            # Import dendritic brave NixOS module
            (if self.modules ? nixos && self.modules.nixos ? brave then self.modules.nixos.brave else { })
          ];
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
            inputs.sops-nix.nixosModules.sops
            # Import dendritic brave NixOS module
            (if self.modules ? nixos && self.modules.nixos ? brave then self.modules.nixos.brave else { })
          ];
        };

        # ISO image for installation
        iso = lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/iso/configuration.nix ];
        };

        # Homeserver
        homeserver = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/homeserver/configuration.nix
            inputs.nixarr.nixosModules.default
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
          ];
        };

        # Boromir - Proxmox VM
        boromir = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/servers/boromir/configuration.nix
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            inputs.quadlet-nix.nixosModules.quadlet
          ];
        };

        # Samwise - Zigbee2MQTT Server (Proxmox VM on the-shire)
        samwise = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/servers/samwise/configuration.nix
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
          ];
        };

        # Theoden - k3s Server + CI/CD (Proxmox VM on rohan)
        theoden = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/servers/theoden/configuration.nix
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            inputs.attic.nixosModules.atticd
            inputs.buildbot-nix.nixosModules.buildbot-master
            inputs.buildbot-nix.nixosModules.buildbot-worker
          ];
        };

      };

      # deploy-rs deployment configuration
      deploy.nodes = {
        boromir = {
          hostname = "boromir.lan";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.boromir;
          };
        };
        samwise = {
          hostname = "samwise.lan";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.samwise;
          };
        };
        theoden = {
          hostname = "theoden.lan";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.theoden;
          };
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

                # Import dendritic crypto module
                (
                  if self.modules ? homeManager && self.modules.homeManager ? crypto then
                    self.modules.homeManager.crypto
                  else
                    { }
                )

                # Import dendritic email module
                (
                  if self.modules ? homeManager && self.modules.homeManager ? email then
                    self.modules.homeManager.email
                  else
                    { }
                )

                # Import dendritic moondeck module
                (
                  if self.modules ? homeManager && self.modules.homeManager ? moondeck then
                    self.modules.homeManager.moondeck
                  else
                    { }
                )

                # Import dendritic opendeck module
                (
                  if self.modules ? homeManager && self.modules.homeManager ? opendeck then
                    self.modules.homeManager.opendeck
                  else
                    { }
                )

                # Import dendritic doom-emacs module
                (
                  if self.modules ? homeManager && self.modules.homeManager ? doom-emacs then
                    self.modules.homeManager.doom-emacs
                  else
                    { }
                )

                # Import play.nix for gamescope integration
                inputs.play-nix.homeManagerModules.play

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
          "ammar@homeserver" = mkHomeConfig ./hosts/homeserver/home.nix;

          # Pixel 9 (Debian AVF with Nix) - aarch64-linux
          "ammar@pixel9" =
            let
              pkgs-aarch64 = import nixpkgs-unstable {
                system = "aarch64-linux";
                config.allowUnfree = true;
              };
              pkgs-stable-aarch64 = import nixpkgs {
                system = "aarch64-linux";
                config.allowUnfree = true;
              };
            in
            home-manager-unstable.lib.homeManagerConfiguration {
              pkgs = pkgs-aarch64;
              extraSpecialArgs = {
                inherit inputs std;
                pkgs-stable = pkgs-stable-aarch64;
              };
              modules = [
                { nixpkgs.overlays = [ inputs.emacs-overlay.overlay ]; }
                (
                  if self.modules ? homeManager && self.modules.homeManager ? doom-emacs then
                    self.modules.homeManager.doom-emacs
                  else
                    { }
                )
                ./hosts/pixel9/home.nix
              ];
            };

          # Fallback configuration (if hostname doesn't match)
          "ammar" = mkHomeConfig ./hosts/profiles/workstation/home.nix;
        };

      # Pre-commit hooks and deploy-rs checks
      checks.${system} = {
        # NixOS system builds (for CI caching)
        nixos-ammars-pc = self.nixosConfigurations.ammars-pc.config.system.build.toplevel;
        nixos-framework13 = self.nixosConfigurations.framework13.config.system.build.toplevel;

        # Home Manager builds (for CI caching)
        home-ammars-pc = self.homeConfigurations."ammar@ammars-pc".activationPackage;
        home-framework13 = self.homeConfigurations."ammar@framework13".activationPackage;

        pre-commit-check = inputs.git-hooks.lib.${system}.run {
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

            # # Custom vulnix hook for vulnerability scanning
            # vulnix = {
            #   enable = true;
            #   name = "vulnix";
            #   description = "Scan for security vulnerabilities in Nix dependencies";
            #   entry = "${pkgs.vulnix}/bin/vulnix --system";
            #   pass_filenames = false;
            #   files = "flake\\.lock$";
            # };

            # Git hygiene
            check-merge-conflicts.enable = true;
            check-added-large-files.enable = true;
            end-of-file-fixer.enable = true;
            trim-trailing-whitespace.enable = true;

            flake-checker.enable = true;

            # Terraform/OpenTofu
            terraform-format.enable = true;
            tflint.enable = true;

            # YAML linting (for K8s manifests)
            yamllint = {
              enable = true;
              settings.configPath = ".yamllint.yaml";
            };

            # Kubernetes manifest validation
            # Disabled: kubeconform requires network to download schemas,
            # which doesn't work in Nix sandbox. Run manually if needed:
            # nix-shell -p kubeconform --run "kubeconform -ignore-missing-schemas -summary k8s/"
            # kubeconform = {
            #   enable = true;
            #   name = "kubeconform";
            #   entry = "${pkgs.kubeconform}/bin/kubeconform -ignore-missing-schemas -summary";
            #   files = "^k8s/.*\\.yaml$";
            #   pass_filenames = true;
            # };
          };
        };
      }
      // deploy-rs.lib.${system}.deployChecks self.deploy;

      # Development shell with pre-commit hooks and deploy-rs
      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit-check) shellHook;
        buildInputs = self.checks.${system}.pre-commit-check.enabledPackages ++ [
          pkgs.opentofu
          pkgs.ansible
          inputs.nvfetcher.packages.${system}.default
          deploy-rs.packages.${system}.default
        ];
      };
    };
}
