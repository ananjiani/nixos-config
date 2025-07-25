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
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      home-manager-unstable,
      nix-std,
      ...
    }@inputs:
    let
      # System configuration
      system = "x86_64-linux";
      lib = nixpkgs-unstable.lib;
      std = nix-std.lib;
      active-profile = import ./active-profile.nix;
      
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

      # Home Manager configurations
      homeConfigurations = {
        ammar = home-manager-unstable.lib.homeManagerConfiguration {
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
            
            # Load profile-specific home configuration
            (./hosts + ("/" + active-profile) + "/home.nix")
          ];
        };
      };
    };
}
