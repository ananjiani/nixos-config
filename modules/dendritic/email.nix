# Dendritic Email Module
# This module follows the dendritic pattern - aspect-oriented configuration
# that can span multiple configuration classes (homeManager, nixos, darwin, etc.)
_:

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

          settings = lib.mkOption {
            type = lib.types.attrs;
            default = { };
            description = "Global Thunderbird settings to apply to all profiles";
            example = lib.literalExpression ''
              {
                "privacy.donottrackheader.enabled" = true;
                "mail.spellcheck.inline" = true;
              }
            '';
          };

          profiles = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  isDefault = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Whether this is the default profile";
                  };

                  settings = lib.mkOption {
                    type = lib.types.attrs;
                    default = { };
                    description = "Profile-specific Thunderbird settings";
                  };
                };
              }
            );
            default = { };
            description = "Thunderbird profiles configuration";
          };
        };

        protonBridge = {
          enable = lib.mkEnableOption "Proton Mail Bridge";

          autostart = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Auto-start Proton Mail Bridge on login via systemd user service";
          };
        };

        # Declarative email accounts for Thunderbird
        accounts = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                address = lib.mkOption {
                  type = lib.types.str;
                  description = "Email address";
                  example = "user@proton.me";
                };

                realName = lib.mkOption {
                  type = lib.types.str;
                  description = "Display name";
                  example = "John Doe";
                };

                imap = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      host = lib.mkOption {
                        type = lib.types.str;
                        default = "127.0.0.1";
                        description = "IMAP server hostname";
                      };
                      port = lib.mkOption {
                        type = lib.types.port;
                        default = 1143;
                        description = "IMAP port";
                      };
                    };
                  };
                  default = { };
                  description = "IMAP configuration";
                };

                smtp = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      host = lib.mkOption {
                        type = lib.types.str;
                        default = "127.0.0.1";
                        description = "SMTP server hostname";
                      };
                      port = lib.mkOption {
                        type = lib.types.port;
                        default = 1025;
                        description = "SMTP port";
                      };
                    };
                  };
                  default = { };
                  description = "SMTP configuration";
                };

                thunderbirdProfiles = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ "default" ];
                  description = "Thunderbird profiles to add this account to";
                };
              };
            }
          );
          default = { };
          description = "Email accounts configuration";
          example = lib.literalExpression ''
            {
              proton = {
                address = "user@proton.me";
                realName = "John Doe";
                imap.host = "127.0.0.1";
                imap.port = 1143;
                smtp.host = "127.0.0.1";
                smtp.port = 1025;
              };
            }
          '';
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
            programs.thunderbird = {
              enable = true;

              inherit (config.email.thunderbird) settings;

              profiles = lib.mkMerge [
                # User-defined profiles
                config.email.thunderbird.profiles

                # Default profile if none specified
                (lib.mkIf (config.email.thunderbird.profiles == { }) {
                  default = {
                    isDefault = true;
                    settings = {
                      # Privacy settings
                      "privacy.donottrackheader.enabled" = true;

                      # Disable auto-update (managed by Nix)
                      "app.update.auto" = false;

                      # Enable inline spell check
                      "mail.spellcheck.inline" = true;

                      # Auto-enable extensions
                      "extensions.autoDisableScopes" = 0;
                    };
                  };
                })
              ];
            };

            # Configure email accounts
            accounts.email.accounts = lib.mapAttrs (_name: accountCfg: {
              inherit (accountCfg) address realName;
              userName = accountCfg.address;

              imap = {
                inherit (accountCfg.imap) host port;
                tls = {
                  enable = true;
                  useStartTls = true;
                };
              };

              smtp = {
                inherit (accountCfg.smtp) host port;
                tls = {
                  enable = true;
                  useStartTls = true;
                };
              };

              thunderbird = {
                enable = true;
                profiles = accountCfg.thunderbirdProfiles;
              };
            }) config.email.accounts;
          })

          # Proton Mail Bridge configuration
          (lib.mkIf config.email.protonBridge.enable {
            home.packages = [ pkgs.protonmail-bridge ];

            # Enable pass for password management (better for non-GNOME environments)
            programs.password-store = {
              enable = true;
              package = pkgs.pass;
            };

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
