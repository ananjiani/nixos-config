{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    sddm-sugar-candy-nix = {
      url = "gitlab:Zhaith-Izaliel/sddm-sugar-candy-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    sops-nix.url = "github:Mic92/sops-nix";
    xremap.url = "github:xremap/nix-flake";
    nil.url = "github:oxalica/nil";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager-unstable
    , sddm-sugar-candy-nix, nix-colors, emacs-overlay, nix-vscode-extensions
    , nixvim, sops-nix, xremap, nil, ... }:
    let
      lib = nixpkgs-unstable.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs-unstable {
        system = "x86_64-linux";
        config = { allowUnfree = true; };
      };
      pkgs-stable = import nixpkgs {
        system = "x86_64-linux";
        config = { allowUnfree = true; };
      };
      active-profile = import ./active-profile.nix;
    in {
      nixosConfigurations = {
        ammars-pc = lib.nixosSystem {
          inherit system;
          modules = [
            sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [ sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/desktop/configuration.nix
          ];
          specialArgs = { inherit pkgs-stable; };
        };
        work-laptop = lib.nixosSystem {
          inherit system;
          modules = [
            sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [ sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/work-laptop/configuration.nix
          ];
          specialArgs = { inherit pkgs-stable; };
        };
        surface-go = lib.nixosSystem {
          inherit system;
          modules = [
            sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [ sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/surface-go/configuration.nix
          ];
          specialArgs = { inherit pkgs-stable; };
        };
      };

      homeConfigurations = {
        ammar = home-manager-unstable.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {
              nixpkgs.overlays = [
                emacs-overlay.overlay
                nix-vscode-extensions.overlays.default
              ];
            }
            (./hosts + ("/" + active-profile) + "/home.nix")
          ];
          extraSpecialArgs = {
            inherit nix-colors;
            inherit nixvim;
            inherit sops-nix;
            inherit xremap;
            inherit pkgs-stable;
            inherit nil;
          };
        };
      };
    };
}
