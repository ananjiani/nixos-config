# HTPC (Home Theater PC) module — Kodi-GBM with ALSA and CEC
# Designed for Intel N100-class devices driving a TV via HDMI
#
# Configures: kodi-gbm (HDR), greetd auto-login, ALSA (bitstream passthrough),
# Intel hardware video decoding, and CEC remote control support.

{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.modules.htpc;
  sources = import ../../_sources/generated.nix {
    inherit (pkgs)
      fetchurl
      fetchFromGitHub
      fetchgit
      dockerTools
      ;
  };

  # Must use kodi-gbm.packages (not pkgs.kodiPackages) so that addons are
  # tagged with kodiAddonFor = kodi-gbm. Using the wrong kodiPackages causes
  # withPackages to silently filter out the addon.
  gbmKodiPackages = pkgs.kodi-gbm.packages;

  # Jacktook — debrid streaming addon (not in nixpkgs, tracked by nvfetcher)
  jacktook = gbmKodiPackages.buildKodiAddon {
    pname = "jacktook";
    namespace = "plugin.video.jacktook";
    version = sources.jacktook.date;

    inherit (sources.jacktook) src;

    # Fix 2-minute playback startup delay: Kodi's InputStream does a GetDirectory
    # probe on URLs before treating them as streams, which hangs for 120s on Comet
    # /playback/ URLs. Fix by checking for a 302 redirect without following it
    # (allow_redirects=False), so we get the CDN URL from the Location header
    # without consuming the stream. If Comet returns 200 (proxy mode), we pass
    # the original URL through unchanged to avoid invalidating it.
    postPatch = ''
      sed -i '/IndexerType.STREMIO_DEBRID\]:/a\        data["url"] = _resolve_stremio_redirect(data.get("url", ""))' lib/utils/player/utils.py
      sed -i '1a\
      def _resolve_stremio_redirect(url):\
          """Resolve Stremio addon 302 redirects to get the direct CDN URL."""\
          try:\
              import requests as _req\
              resp = _req.get(url, stream=True, allow_redirects=False, timeout=15)\
              resp.close()\
              if resp.status_code in (301, 302, 303, 307, 308):\
                  cdn_url = resp.headers.get("Location", url)\
                  from lib.jacktook.utils import kodilog as _log\
                  _log(f"Resolved redirect: {cdn_url[:80]}")\
                  return cdn_url\
              return url\
          except Exception:\
              return url\
      ' lib/utils/player/utils.py
    '';

    propagatedBuildInputs = with gbmKodiPackages; [
      requests
      routing
    ];

    passthru.pythonPath = "lib";

    meta = {
      homepage = "https://github.com/Sam-Max/plugin.video.jacktook";
      description = "Torrent streaming addon for Kodi with debrid support";
      license = lib.licenses.gpl2Only;
    };
  };

  kodiPkg = pkgs.kodi-gbm.withPackages (kp: [
    kp.inputstream-adaptive # ABR streaming (HLS, DASH, Smooth Streaming)
    kp.inputstream-ffmpegdirect # Direct stream playback via FFmpeg
    jacktook # Debrid streaming + built-in Trakt sync (Comet, TorBox)
  ]);
in
{
  options.modules.htpc = {
    enable = lib.mkEnableOption "HTPC configuration with Kodi-GBM";

    kodiUser = lib.mkOption {
      type = lib.types.str;
      default = "kodi";
      description = "Username for the Kodi service user";
    };
  };

  config = lib.mkIf cfg.enable {
    # Kodi-GBM with streaming addons + CEC/video utilities
    environment.systemPackages = [
      kodiPkg
      pkgs.libcec # CEC control library (used by Kodi for TV remote)
      pkgs.v4l-utils # Includes cec-ctl for CEC debugging
    ];

    # Dedicated user for Kodi (no password, auto-login only)
    users.users.${cfg.kodiUser} = {
      isNormalUser = true;
      description = "Kodi Media Center";
      extraGroups = [
        "video" # GPU access
        "audio" # ALSA devices
        "input" # Input devices (CEC, IR)
        "render" # DRM render nodes
      ];
    };

    # ALSA only — PipeWire/PulseAudio interfere with HDMI bitstream passthrough
    hardware = {
      alsa.enable = true;
      # Intel Gen12+ graphics (N100 = Alder Lake-N)
      graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver # iHD VA-API driver (HEVC, VP9, AV1 decode)
        ];
      };
    };

    services = {
      # Auto-login directly to Kodi standalone (no display manager)
      greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${kodiPkg}/bin/kodi-standalone";
            user = cfg.kodiUser;
          };
          default_session = {
            command = "${kodiPkg}/bin/kodi-standalone";
            user = cfg.kodiUser;
          };
        };
      };
      pulseaudio.enable = false;
      pipewire.enable = false;
      # CEC device permissions — allow video group to access /dev/cec*
      udev.extraRules = ''
        KERNEL=="cec[0-9]*", GROUP="video", MODE="0660"
      '';
    };

    # Kodi web interface (8080) and JSON-RPC (9090) for remote control apps
    networking.firewall.allowedTCPPorts = [
      8080
      9090
    ];
  };
}
