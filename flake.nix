{
  description = "My first flake!";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sddm-sugar-candy-nix = {
      url = "gitlab:Zhaith-Izaliel/sddm-sugar-candy-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
  };

  outputs = {self, nixpkgs, home-manager, sddm-sugar-candy-nix, nix-colors, emacs-overlay, ...}:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs { system = "x86_64-linux"; config = { allowUnfree = true; }; };
      active-profile = import ./active-profile.nix;
    in {
      nixosConfigurations = {
        ammars-pc = lib.nixosSystem {
          inherit system;
          modules = [
            sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [
                  sddm-sugar-candy-nix.overlays.default
                ];
              };
            }
            ./profiles/desktop/configuration.nix
          ];
        };
        work-laptop = lib.nixosSystem {
          inherit system;
          modules = [
            sddm-sugar-candy-nix.nixosModules.default
            {
              nixpkgs = {
                overlays = [
                  sddm-sugar-candy-nix.overlays.default
                ];
              };
            }
            ./profiles/work-laptop/configuration.nix
          ];
        };
      };

      homeConfigurations = {
 	      ammar = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {nixpkgs.overlays = [emacs-overlay.overlay];}
            (./profiles + ("/" + active-profile) + "/home.nix")
          ];
          extraSpecialArgs = { inherit nix-colors; };
        };
      };
    };
}
