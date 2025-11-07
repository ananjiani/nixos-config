# Dendritic Email Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
{ inputs, ... }:

{
  # Home Manager configuration (user-level email applications)
  flake.aspects.email.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.email = {
        enable = lib.mkEnableOption "email applications and services";

        thunderbird = {
          enable = lib.mkEnableOption "Mozilla Thunderbird email client";
        };

        protonBridge = {
          enable = lib.mkEnableOption "Proton Mail Bridge";
          
          autostart = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Auto-start Proton Mail Bridge on login via systemd user service";
          };
        };

        # Future: Add support for other email clients
        # mu4e = {
        #   enable = lib.mkEnableOption "mu4e email client for Emacs";
        # };
        # aerc = {
        #   enable = lib.mkEnableOption "aerc terminal email client";
        # };
      };

      config = lib.mkIf config.email.enable (
        lib.mkMerge [
          # Thunderbird configuration
          (lib.mkIf config.email.thunderbird.enable {
            home.packages = [ pkgs.thunderbird ];
          })

          # Proton Mail Bridge configuration
          (lib.mkIf config.email.protonBridge.enable {
            home.packages = [ pkgs.protonmail-bridge ];

            # Optional: Auto-start Proton Mail Bridge via systemd user service
            systemd.user.services.protonmail-bridge = lib.mkIf config.email.protonBridge.autostart {
              Unit = {
                Description = "Proton Mail Bridge";
                After = [ "graphical-session.target" ];
              };

              Service = {
                Type = "simple";
                ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
                Restart = "on-failure";
                RestartSec = "5s";
                
                # Environment variables for consistent runtime
                Environment = [
                  "PATH=${pkgs.lib.makeBinPath [ pkgs.gnome-keyring ]}"
                ];
              };

              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };
          })
        ]
      );
    };

  # Future: NixOS system-level email services
  # Uncomment and expand when you need system-level email functionality
  # flake.modules.nixos.email = { pkgs, lib, config, ... }: {
  #   options.services.email = {
  #     # System-level email services (mail servers, relay, etc.)
  #   };
  #   config = {
  #     # System-level configuration
  #   };
  # };

  # Future: macOS support via nix-darwin
  # Uncomment when you need macOS email support
  # flake.modules.darwin.email = { pkgs, lib, config, ... }: {
  #   # macOS-specific email tools and services
  # };
}
