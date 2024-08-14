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
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager
    , home-manager-unstable, nix-std, ... }@inputs:
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
      std = nix-std.lib;
      active-profile = import ./active-profile.nix;
    in {
      nix.nixPath = [ "nixpkgs=${nixpkgs-unstable}" ];
      nixosConfigurations = {
        ammars-pc = lib.nixosSystem {
          inherit system;
          modules = [ ./hosts/desktop/configuration.nix ];
          specialArgs = { inherit pkgs-stable; };
        };
        work-laptop = lib.nixosSystem {
          inherit system;
          modules = [ ./hosts/work-laptop/configuration.nix ];
          specialArgs = { inherit pkgs-stable; };
        };
        surface-go = lib.nixosSystem {
          inherit system;
          modules = [ ./hosts/surface-go/configuration.nix ];
          specialArgs = { inherit pkgs-stable; };
        };
        framework13 = lib.nixosSystem {
          inherit system;
          modules = [
            ./hosts/framework13/configuration.nix
            inputs.nixos-hardware.nixosModules.framework-13-7040-amd
          ];
          specialArgs = { inherit pkgs-stable; };
        };
        iso = lib.nixosSystem {
          inherit system;
          modules = [ ./hosts/iso/configuration.nix ];
          specialArgs = { inherit pkgs-stable; };
        };
        router = lib.nixosSystem {
          inherit system;
          modules = [
            inputs.proxmox-nixos.nixosModules.proxmox-ve
            ./hosts/router/configuration.nix
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
                inputs.emacs-overlay.overlay
                inputs.nix-vscode-extensions.overlays.default
              ];
            }
            (./hosts + ("/" + active-profile) + "/home.nix")
          ];
          extraSpecialArgs = { inherit inputs std pkgs-stable; };

        };
      };
    };
}
