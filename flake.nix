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
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    sops-nix.url = "github:Mic92/sops-nix";
    xremap.url = "github:xremap/nix-flake";
    hyprland.url = "github:hyprwm/Hyprland";
    waybar.url = "github:alexays/waybar";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager
    , home-manager-unstable, ... }@inputs:
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
            inputs.sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [ inputs.sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/desktop/configuration.nix
          ];
          specialArgs = { inherit pkgs-stable; };
        };
        work-laptop = lib.nixosSystem {
          inherit system;
          modules = [
            inputs.sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [ inputs.sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/work-laptop/configuration.nix
          ];
          specialArgs = { inherit pkgs-stable; };
        };
        surface-go = lib.nixosSystem {
          inherit system;
          modules = [
            inputs.sddm-sugar-candy-nix.nixosModules.default
            inputs.hyprland.nixosModules.default
            {
              nixpkgs = {
                overlays = [ inputs.sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/surface-go/configuration.nix
          ];
          specialArgs = { inherit pkgs-stable; };
        };
        framework13 = lib.nixosSystem {
          inherit system;
          modules = [
            inputs.sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [ inputs.sddm-sugar-candy-nix.overlays.default ];
              };
            }
            ./hosts/framework13/configuration.nix
            inputs.nixos-hardware.nixosModules.framework-13-7040-amd
          ];
          specialArgs = { inherit pkgs-stable; };
        };
      };

      homeConfigurations = {
        ammar = home-manager-unstable.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            inputs.hyprland.homeManagerModules.default
            {
              nixpkgs.overlays = [
                inputs.emacs-overlay.overlay
                inputs.nix-vscode-extensions.overlays.default
              ];
            }
            (./hosts + ("/" + active-profile) + "/home.nix")
          ];
          extraSpecialArgs = { inherit inputs; };
        };
      };
    };
}
