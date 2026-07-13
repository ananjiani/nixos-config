{
  config,
  lib,
  pkgs,
  ...
}:

let
  # DP-2 (HDR ultrawide) output block lives in a writable include so HDR can be
  # toggled at runtime. niri looks up outputs by first-match with no merging, so
  # the block must exist ONLY here (not in programs.niri.settings.outputs), else
  # a duplicate would shadow this one. hdr-on/hdr-off swap this file and niri
  # live-reloads. mode="auto" keeps the SDR desktop clean; mode="on" makes DP-2
  # advertise HDR upfront (needed by games that probe HDR only at swapchain
  # creation, e.g. AC4 — auto's chicken-and-egg never engages for them).
  # reference-luminance = nits that SDR white (1.0) maps to while DP-2 is in HDR
  # mode, and the reference white of the blend space the game's HDR is composited
  # into. 203 is the BT.2408 default; raise if HDR looks washed/lifted, lower if
  # crushed. Panel is DisplayHDR True Black 400 (EDID: 400 peak / 248 avg).
  hdrReferenceLuminance = 203;
  dp2Fragment =
    hdrMode:
    pkgs.writeText "niri-dp2-${hdrMode}.kdl" ''
      output "DP-2" {
          hdr mode="${hdrMode}" {
              reference-luminance ${toString hdrReferenceLuminance}
          }
          scale 1.000000
          transform "normal"
          position x=0 y=1440
          mode "5120x1440@239.761000"
          variable-refresh-rate on-demand=true
      }
    '';
  dp2Auto = dp2Fragment "auto";
  dp2On = dp2Fragment "on";
  hdrFragmentPath = "$HOME/.config/niri/hdr.kdl";
in
{
  # Enable SSH agent for SSH key management
  services.ssh-agent.enable = true;

  # SSH askpass for passphrase prompts
  home = {
    packages = [
      pkgs.lxqt.lxqt-openssh-askpass
      # Runtime DP-2 HDR toggle (rewrites the niri include; niri live-reloads)
      (pkgs.writeShellScriptBin "hdr-on" ''
        install -m 0644 ${dp2On} "${hdrFragmentPath}"
        echo "DP-2 HDR: on (niri live-reloads)"
      '')
      (pkgs.writeShellScriptBin "hdr-off" ''
        install -m 0644 ${dp2Auto} "${hdrFragmentPath}"
        echo "DP-2 HDR: auto"
      '')
    ];
    sessionVariables.SSH_ASKPASS = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";
    shellAliases = {
      fab = ''BROWSER="flatpak run com.microsoft.Edge %s" mullvad-exclude fab'';
    };
  };

  imports = [
    ../_profiles/workstation/home.nix
    # crypto.nix is now imported via dendritic pattern in flake.nix
    ../../modules/home/config/sops.nix
    ../../modules/home/dev/tea.nix
  ];

  desktop = {
    niri = {
      enable = true;
      screenProfile = "ultrawide";
    };
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

  gaming = {
    enable = true;
    syncthing.enable = true;
    ludusavi.backupPath = "/home/ammar/Games/Saves/ammars-pc";
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

  # Experimental HDR fork (must match NixOS programs.niri.package)
  programs.niri.package = pkgs.niri-hdr;

  # niri-flake's schema has no `hdr` key and DP-2 lives in a writable include
  # (see dp2Fragment above), so append the include to the generated config.
  # optional=true keeps niri happy if the fragment isn't written yet.
  xdg.configFile.niri-config.source = lib.mkForce (
    pkgs.writeText "niri-config.kdl" (
      config.programs.niri.finalConfig
      + ''

        include "~/.config/niri/hdr.kdl" optional=true
      ''
    )
  );

  # Seed the HDR fragment (auto) on every switch; hdr-on/hdr-off swap it live.
  home.activation.niriHdrFragment = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/niri"
    run install -m 0644 ${dp2Auto} "${hdrFragmentPath}"
  '';

  # niri output/workspace layout (mirrors the hyprland monitor/workspace block above)
  programs.niri.settings = {
    outputs = {
      # NOTE: DP-2 (HDR ultrawide) is intentionally NOT here — it's defined in the
      # writable include ~/.config/niri/hdr.kdl (see dp2Fragment) for runtime HDR
      # toggling. Putting it here too would shadow that block (first-match wins).

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

    # Persistent workspaces pinned to monitors
    workspaces = {
      "main".open-on-output = "DP-2";
      "reading".open-on-output = "DP-2";
      "work".open-on-output = "DP-2";
      "chat".open-on-output = "HDMI-A-1";
      "media".open-on-output = "DP-1";
    };
  };
}
