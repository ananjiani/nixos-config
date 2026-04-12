{
  lib,
  pkgs,
  ...
}:

{
  # Enable SSH agent for SSH key management
  services.ssh-agent.enable = true;

  # SSH askpass for passphrase prompts
  home.packages = [ pkgs.lxqt.lxqt-openssh-askpass ];
  home.sessionVariables.SSH_ASKPASS = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";

  imports = [
    ../_profiles/workstation/home.nix
    ../../modules/home/gaming.nix
    # crypto.nix is now imported via dendritic pattern in flake.nix
    ../../modules/home/config/sops.nix
  ];

  desktop = {
    niri.enable = true;
    wallpaper.mode = lib.mkForce "fit";
    hyprland.persistentWorkspaces = {
      "DP-2" = [
        1
        2
        3
      ];
      "HDMI-A-1" = [ 4 ];
      "DP-1" = [ 5 ];
    };
  };

  crypto = {
    enable = true;
    cakewallet.enable = true;
  };

  moondeck = {
    enable = true;
    autostart = true; # headless mode via systemd
  };

  opendeck = {
    enable = true;
    # plugins = [ ]; # Add plugins later
    # seedProfiles = { }; # Add starter profiles later
  };

  # Monitor configuration for play.nix (mix.nix namespace)
  monitors = [
    {
      name = "DP-2"; # Main gaming monitor
      primary = true;
      width = 5120;
      height = 1440;
      refreshRate = 240;
      hdr = true;
      vrr = true;
    }
  ];

  # play.nix - gamescope integration for HDR/VRR gaming
  play = {
    gamescoperun = {
      enable = true;
      defaultHDR = true;
      defaultSystemd = true; # Isolate gaming sessions with systemd-run
    };
    wrappers.steam-gamescope = {
      enable = true;
      useHDR = true;
      command = "steam";
      environment = {
        MANGOHUD = "1";
      };
      extraOptions = {
        force-windows-fullscreen = true;
      };
    };
  };

  # email = {
  #   enable = true;
  #   thunderbird = {
  #     enable = true;

  #     # Enable ALL hardened settings from thunderbird-user.js
  #     useHardenedUserJs = true;

  #     # Auto-start and minimize to tray (handled by birdtray)
  #     autostart = true;

  #     # Enable Birdtray for system tray integration on Linux
  #     birdtray.enable = true;

  #     userPrefs = {
  #       # ProtonMail Bridge certificate was accepted during setup
  #       # Can now use strict pinning (2) for better security
  #       # Note: If you have issues, temporarily set to 1
  #       "security.cert_pinning.enforcement_level" = 2;
  #     };
  #   };
  #   protonBridge = {
  #     enable = true;
  #     autostart = true;
  #   };
  #   accounts = {
  #     proton = {
  #       address = "ammar.nanjiani@pm.me";
  #       realName = "Ammar Nanjiani";
  #       primary = true;
  #       imap = {
  #         host = "127.0.0.1";
  #         port = 1143;
  #       };
  #       smtp = {
  #         host = "127.0.0.1";
  #         port = 1025;
  #       };
  #       thunderbirdProfiles = [ "default" ];
  #       # Password from SOPS - the ProtonMail Bridge generated password
  #       passwordFile = config.sops.secrets.proton_bridge_password.path;
  #     };
  #   };
  # };

  wayland.windowManager.hyprland.settings = {
    # experimental = {
    #   xx_color_management_v4 = true;
    # };
    monitor = [
      "DP-2,5120x1440@240,0x1440,1,vrr,2" # bitdepth,10,cm,hdr,sdrbrightness,1.2,sdrsaturation,1.1
      "DP-1,3840x2160@60,2560x0,1.5"
      "HDMI-A-1,2560x1440@60,0x0,1"
    ];
    workspace = [
      # Main monitor (DP-2) - workspaces 1-3 for focused work (always visible)
      "1, monitor:DP-2, default:true, layoutopt:orientation:center, persistent:true"
      "2, monitor:DP-2, layoutopt:orientation:center, persistent:true"
      "3, monitor:DP-2, layoutopt:orientation:center, persistent:true"

      # Left monitor (HDMI-A-1) - workspace 4 for communication (dwindle for multiple chats)
      "4, monitor:HDMI-A-1, default:true, persistent:true"

      # Right monitor (DP-1) - workspace 5 for media/reference
      "5, monitor:DP-1, default:true, persistent:true"
    ];
    exec-once = [
      "corectrl"
      "steam -silent -cef-disable-gpu"
    ];
  };

  # niri output/workspace layout (mirrors the hyprland monitor/workspace block above)
  programs.niri.settings = {
    outputs = {
      # Main ultrawide — 5120x1440 @ 240Hz, VRR fullscreen-only (matches hyprland's "vrr,2")
      "DP-2" = {
        mode = {
          width = 5120;
          height = 1440;
          refresh = 239.761;
        };
        position = {
          x = 0;
          y = 1440;
        };
        scale = 1.0;
        variable-refresh-rate = "on-demand";
      };

      # Right 4K @ scale 1.5 → 2560x1440 logical footprint, placed to the right of HDMI-A-1
      "DP-1" = {
        mode = {
          width = 3840;
          height = 2160;
          refresh = 60.0;
        };
        position = {
          x = 2560;
          y = 0;
        };
        scale = 1.5;
      };

      # Left 1440p @ scale 1, top-left corner of the logical layout
      "HDMI-A-1" = {
        mode = {
          width = 2560;
          height = 1440;
          refresh = 60.0;
        };
        position = {
          x = 0;
          y = 0;
        };
        scale = 1.0;
      };
    };

    # Persistent workspaces pinned to monitors, matching hyprland's layout
    # (1-3 on DP-2, 4 on HDMI-A-1, 5 on DP-1)
    workspaces = {
      "01-main-1".open-on-output = "DP-2";
      "02-main-2".open-on-output = "DP-2";
      "03-main-3".open-on-output = "DP-2";
      "04-chat".open-on-output = "HDMI-A-1";
      "05-media".open-on-output = "DP-1";
      "05-reading".open-on-output = "DP-2";
    };
  };
}
