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
      url = "github:k3d3/claude-desktop-linux-flake/b2b040cb68231d2118906507d9cc8fd181ca6308";
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
    mix-nix = {
      url = "github:tophc7/mix.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    play-nix = {
      url = "github:TophC7/play.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.mix-nix.follows = "mix-nix";
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
    comfyui-nix = {
      url = "github:utensils/comfyui-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    mkdocs-flake = {
      url = "github:applicative-systems/mkdocs-flake";
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

      # Separate documentation flake (decoupled from dendritic modules)
      documentationFlake = flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [
          system
          "aarch64-linux"
        ];
        imports = [ inputs.mkdocs-flake.flakeModules.default ];
        perSystem = _: {
          documentation.mkdocs-root = ./docs;
        };
      };
    in
    {
      # Expose dendritic modules for consumption (underscore prefix hides from flake output warnings)
      _modules = dendriticFlake.modules or { };

      # NixOS system configurations
      nixosConfigurations = {
        # Desktop system
        ammars-pc = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/desktop/configuration.nix
            inputs.sops-nix.nixosModules.sops
            # Import dendritic moondeck NixOS module
            (
              if self._modules ? nixos && self._modules.nixos ? moondeck then
                self._modules.nixos.moondeck
              else
                { }
            )
            # Import dendritic opendeck NixOS module
            (
              if self._modules ? nixos && self._modules.nixos ? opendeck then
                self._modules.nixos.opendeck
              else
                { }
            )
            # Import dendritic brave NixOS module
            (if self._modules ? nixos && self._modules.nixos ? brave then self._modules.nixos.brave else { })
          ];
        };

        # Framework 13 laptop
        framework13 = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/framework13/configuration.nix
            inputs.nixos-hardware.nixosModules.framework-13-7040-amd
            inputs.sops-nix.nixosModules.sops
            # Import dendritic brave NixOS module
            (if self._modules ? nixos && self._modules.nixos ? brave then self._modules.nixos.brave else { })
          ];
        };

        # ISO image for installation
        iso = lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/iso/configuration.nix ];
        };

        # Boromir - Proxmox VM
        boromir = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/servers/boromir/configuration.nix
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
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

        # Pippin - Clawdbot AI Assistant (Proxmox VM on the-shire)
        pippin = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/servers/pippin/configuration.nix
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
          ];
        };

        # Rivendell - HTPC (Intel N100 bare metal)
        rivendell = lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./hosts/servers/rivendell/configuration.nix
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            # Dendritic kodi NixOS module (SOPS secret injection)
            (if self._modules ? nixos && self._modules.nixos ? kodi then self._modules.nixos.kodi else { })
            # Dendritic kodi HM module (advancedsettings.xml) — via sharedModules
            (
              if self._modules ? homeManager && self._modules.homeManager ? kodi then
                {
                  home-manager.sharedModules = [ self._modules.homeManager.kodi ];
                }
              else
                { }
            )
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
        pippin = {
          hostname = "pippin.lan";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.pippin;
          };
        };
        rivendell = {
          hostname = "rivendell.lan";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.rivendell;
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
                  if self._modules ? homeManager && self._modules.homeManager ? crypto then
                    self._modules.homeManager.crypto
                  else
                    { }
                )

                # Import dendritic email module
                (
                  if self._modules ? homeManager && self._modules.homeManager ? email then
                    self._modules.homeManager.email
                  else
                    { }
                )

                # Import dendritic moondeck module
                (
                  if self._modules ? homeManager && self._modules.homeManager ? moondeck then
                    self._modules.homeManager.moondeck
                  else
                    { }
                )

                # Import dendritic opendeck module
                (
                  if self._modules ? homeManager && self._modules.homeManager ? opendeck then
                    self._modules.homeManager.opendeck
                  else
                    { }
                )

                # Import dendritic doom-emacs module
                (
                  if self._modules ? homeManager && self._modules.homeManager ? doom-emacs then
                    self._modules.homeManager.doom-emacs
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
          "ammar@framework13" = mkHomeConfig ./hosts/framework13/home.nix;

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
                  if self._modules ? homeManager && self._modules.homeManager ? doom-emacs then
                    self._modules.homeManager.doom-emacs
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

        # Server NixOS builds (includes home-manager, cached for deploy-rs checks)
        nixos-boromir = self.nixosConfigurations.boromir.config.system.build.toplevel;
        nixos-samwise = self.nixosConfigurations.samwise.config.system.build.toplevel;
        nixos-theoden = self.nixosConfigurations.theoden.config.system.build.toplevel;
        nixos-pippin = self.nixosConfigurations.pippin.config.system.build.toplevel;
        nixos-rivendell = self.nixosConfigurations.rivendell.config.system.build.toplevel;

        # Home Manager builds (for CI caching)
        home-ammars-pc = self.homeConfigurations."ammar@ammars-pc".activationPackage;
        home-framework13 = self.homeConfigurations."ammar@framework13".activationPackage;

        # DevShell (cached in Attic for faster `nix develop` across machines)
        devshell = self.devShells.${system}.default;

        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            # First run formatters
            nixfmt.enable = true;

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

      # Packages from documentationFlake (mkdocs-flake) plus utilities
      packages.${system} = (documentationFlake.packages.${system} or { }) // {
        inherit (pkgs) attic-client;
      };

      # Apps from documentationFlake (mkdocs-flake watch-documentation)
      apps.${system} = documentationFlake.apps.${system} or { };

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
