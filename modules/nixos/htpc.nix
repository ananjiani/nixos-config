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

  # Jacktook — debrid streaming addon (not in nixpkgs)
  jacktook = pkgs.kodiPackages.buildKodiAddon rec {
    pname = "jacktook";
    namespace = "plugin.video.jacktook";
    version = "0.24.0";

    src = pkgs.fetchFromGitHub {
      owner = "Sam-Max";
      repo = "plugin.video.jacktook";
      rev = "2173568d144455d1c4928e23b4b142d51c63e111";
      hash = "sha256-AJXMOt6p3qqjaLV+U/gg38R2fFuClLQGojOn0OA5YsU=";
    };

    propagatedBuildInputs = with pkgs.kodiPackages; [
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
    kp.trakt # Watch history sync across devices
    jacktook # Debrid streaming (Prowlarr, Comet, TorBox)
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
