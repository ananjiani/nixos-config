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
          mode "5120x1440@240.000"
          variable-refresh-rate on-demand=true
      }
    '';
  dp2Auto = dp2Fragment "auto";
  dp2On = dp2Fragment "on";
  hdrFragmentPath = "$HOME/.config/niri/hdr.kdl";
  sunshineFragmentPath = "$HOME/.config/niri/sunshine.kdl";
  hdrOn = pkgs.writeShellScriptBin "hdr-on" ''
    install -m 0644 ${dp2On} "${hdrFragmentPath}"
    echo "DP-2 HDR: on (niri live-reloads)"
  '';
  hdrOff = pkgs.writeShellScriptBin "hdr-off" ''
    install -m 0644 ${dp2Auto} "${hdrFragmentPath}"
    echo "DP-2 HDR: auto"
  '';
  gamescopeHdr = pkgs.writeShellApplication {
    name = "gamescope-hdr";
    text = ''
      width=5120
      height=1440
      refresh=240
      hdr_args=(--hdr-enabled)
      game_env=(${pkgs.coreutils}/bin/env ENABLE_HDR_WSI=1 DXVK_HDR=1)

      if [ -f "${sunshineFragmentPath}" ]; then
        if ${pkgs.gnugrep}/bin/grep -Fq 'mode custom=true "1920x1200@90"' "${sunshineFragmentPath}"; then
          width=1920
          height=1200
          refresh=90
        elif ${pkgs.gnugrep}/bin/grep -Fq 'mode custom=true "1920x1080@120"' "${sunshineFragmentPath}"; then
          width=1920
          height=1080
          refresh=120
        else
          echo "unsupported Sunshine niri fragment" >&2
          exit 1
        fi

        if ! ${pkgs.gnugrep}/bin/grep -Fq 'hdr mode="on"' "${sunshineFragmentPath}"; then
          hdr_args=()
          game_env=(${pkgs.coreutils}/bin/env -u ENABLE_HDR_WSI -u DXVK_HDR)
        fi
      else
        ${hdrOn}/bin/hdr-on
        trap '${hdrOff}/bin/hdr-off' EXIT
        sleep 1
      fi

      ${pkgs.gamescope}/bin/gamescope \
        -W "$width" -H "$height" -w "$width" -h "$height" -r "$refresh" -f \
        "''${hdr_args[@]}" --virtual-connector-strategy PerWindow \
        -- "''${game_env[@]}" "$@"
    '';
  };
  # Upstream static pi-web binary — web UI for local Pi coding-agent sessions.
  # HTTPS edge lives in k8s Traefik (see ADR-006); this binds to the desktop's
  # LAN IP and is protected by PI_WEB_TOKEN from ~/.config/pi-web/env (never in
  # the store).
  # Reduced scope (ADR-006): the standalone binary is used WITHOUT the upstream
  # Pi package extensions/skills, so /web, /remote, /refresh, the token
  # commands, the ask-user tool, and the memory skill are unavailable in
  # terminal Pi; browser chat works, and returning to the terminal means
  # reopening/resuming the session rather than /refresh.
  piWeb = pkgs.stdenvNoCC.mkDerivation {
    pname = "pi-web";
    version = "0.0.1-beta.34";
    src = pkgs.fetchurl {
      url = "https://github.com/ygncode/pi-web/releases/download/v0.0.1-beta.34/pi-web-linux-amd64";
      hash = "sha256-SQsdtyHNBfNECq3w/4SdBd32jcWl3xUTbeRv7gkve9I=";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 $src $out/bin/pi-web
    '';
  };
  # pi-web's in-app updater tries to imperatively `pi install
  # npm:@ygncode/pi-web@beta`, which would fight the Nix-managed binary above.
  # This shim (first in the service PATH) blocks only that; every other
  # invocation — including the `pi --mode rpc` workers pi-web spawns — execs
  # the real pi.
  piShim = pkgs.writeShellScriptBin "pi" ''
    if [ "''${1:-}" = "install" ]; then
      for arg in "$@"; do
        case "$arg" in
          "npm:@ygncode/pi-web"*)
            echo "pi-web is Nix-managed (hosts/desktop/home.nix); refusing 'pi install $arg'. Bump the pinned version there instead." >&2
            exit 1
            ;;
        esac
      done
    fi
    exec ${pkgs.llm-agents.pi}/bin/pi "$@"
  '';
  # Idempotent PI_WEB_TOKEN provisioning: keep a valid existing token, replace
  # only a missing/malformed PI_WEB_TOKEN line, preserve unrelated env lines,
  # never print the token. Nonzero exit fails HM activation.
  piWebEnvSetup = pkgs.writeShellScript "pi-web-env-setup" ''
    set -euo pipefail
    umask 077
    dir="$HOME/.config/pi-web"
    env_file="$dir/env"
    mkdir -p "$dir"
    chmod 0700 "$dir"
    token_lines=0
    if [ -e "$env_file" ]; then
      if token_lines="$(grep -Ec '^[[:space:]]*PI_WEB_TOKEN=' "$env_file")"; then
        :
      else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
      fi
    fi
    if [ "$token_lines" -eq 1 ] && grep -Eqs '^PI_WEB_TOKEN=[0-9a-f]{64}$' "$env_file"; then
      chmod 0600 "$env_file"
      exit 0
    fi
    token="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
    printf '%s' "$token" | grep -Eq '^[0-9a-f]{64}$'
    tmp="$(mktemp "$dir/env.XXXXXX")"
    if [ -f "$env_file" ]; then
      if grep -Ev '^[[:space:]]*PI_WEB_TOKEN=' "$env_file" > "$tmp"; then
        :
      else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
      fi
    fi
    printf 'PI_WEB_TOKEN=%s\n' "$token" >> "$tmp"
    mv "$tmp" "$env_file"
    chmod 0600 "$env_file"
  '';
  # systemd user units get a minimal PATH; pi sessions spawned by pi-web need
  # the usual user toolchains (npm globals, HM profile, setuid wrappers, ...).
  # piShim must come first so pi-web's updater can't bypass it.
  piWebLaunch = pkgs.writeShellScript "pi-web-launch" ''
    export PATH="${piShim}/bin:$HOME/.local/bin:$HOME/.npm-global/bin:${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    exec ${piWeb}/bin/pi-web -host 192.168.1.50
  '';
in
{
  # Enable SSH agent for SSH key management
  services.ssh-agent.enable = true;

  # SSH askpass for passphrase prompts
  home = {
    packages = [
      pkgs.lxqt.lxqt-openssh-askpass
      # Runtime DP-2 HDR helpers (niri live-reloads hdr.kdl).
      hdrOn
      hdrOff
      gamescopeHdr
      piWeb
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

  # niri-flake's schema has no `hdr` key. Sunshine's optional include comes
  # first so its active DP-3 profile shadows the generated DP-3 `off` block;
  # removing it restores that safe idle default. DP-2 remains in hdr.kdl.
  xdg.configFile.niri-config.source = lib.mkForce (
    pkgs.writeText "niri-config.kdl" (
      ''
        include "~/.config/niri/sunshine.kdl" optional=true

      ''
      + config.programs.niri.finalConfig
      + ''

        include "~/.config/niri/hdr.kdl" optional=true
      ''
    )
  );

  home.activation = {
    # Seed the HDR fragment (auto) on every switch; hdr-on/hdr-off swap it live.
    niriHdrFragment = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/.config/niri"
      run install -m 0644 ${dp2Auto} "${hdrFragmentPath}"
    '';

    # Provision PI_WEB_TOKEN in ~/.config/pi-web/env (0700 dir, 0600 file).
    # The token is written straight to the file — never in the Nix store,
    # never echoed. See piWebEnvSetup above.
    piWebEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${piWebEnvSetup}
    '';
  };

  # LAN-bound pi-web; reachable as https://pi.dimensiondoor.xyz via the k8s
  # Traefik edge (selectorless Service → 192.168.1.50:31415). See ADR-006.
  systemd.user.services.pi-web = {
    Unit.Description = "pi-web (Pi coding agent web UI)";
    Service = {
      ExecStart = toString piWebLaunch;
      EnvironmentFile = "-%h/.config/pi-web/env";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # niri output/workspace layout (mirrors the hyprland monitor/workspace block above)
  programs.niri.settings = {
    outputs = {
      # NOTE: DP-2 (HDR ultrawide) is intentionally NOT here — it's defined in the
      # writable include ~/.config/niri/hdr.kdl (see dp2Fragment) for runtime HDR
      # toggling. Putting it here too would shadow that block (first-match wins).

      # Sunshine stream connector (fake EDID). Off until global_prep_cmd enables it.
      "DP-3" = {
        enable = false;
        mode = {
          width = 1280;
          height = 800;
        };
        scale = 1.0;
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

    # Persistent workspaces pinned to monitors
    workspaces = {
      "main".open-on-output = "DP-2";
      "reading".open-on-output = "DP-2";
      "work".open-on-output = "DP-2";
      "chat".open-on-output = "HDMI-A-1";
      "media".open-on-output = "DP-1";
      "gaming".open-on-output = "DP-2";
    };
  };
}
