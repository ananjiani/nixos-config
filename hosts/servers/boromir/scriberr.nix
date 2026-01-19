# Scriberr - AI-powered audio transcription
#
# Runs as a Podman container via quadlet-nix with NVIDIA GPU acceleration.
# Uses WhisperX for fast, accurate transcription with speaker diarization.
{ lib, ... }:

{
  # Enable Podman for quadlet containers (Docker stays for model conversion)
  virtualisation.podman = {
    enable = true;
    dockerCompat = false; # Don't override docker command
  };

  # CDI workaround for nvidia-container-toolkit issues
  # See: https://github.com/NixOS/nixpkgs/issues/463525
  systemd.services.nvidia-container-toolkit-cdi-generator.serviceConfig.ExecStartPre =
    lib.mkForce null;

  # Create local directories for Scriberr data
  # Using local storage because SQLite has locking issues on NFS
  # 777 permissions required - container switches to UID 1000 internally
  systemd.tmpfiles.rules = [
    "d /var/lib/scriberr 0777 root root -"
    "d /var/lib/scriberr/data 0777 root root -"
    "d /var/lib/scriberr/whisperx-env 0777 root root -"
  ];

  # Quadlet container configuration
  virtualisation.quadlet.containers.scriberr = {
    autoStart = true;

    containerConfig = {
      image = "ghcr.io/rishikanthc/scriberr-cuda:v1.2.0";
      publishPorts = [ "8080:8080" ];
      # Use local storage for database (SQLite has issues on NFS)
      # NFS can still be used for uploads/transcripts manually
      volumes = [
        "/var/lib/scriberr/data:/app/data"
        "/var/lib/scriberr/whisperx-env:/app/whisperx-env"
      ];
      environments = {
        PUID = "1000";
        PGID = "1000";
        APP_ENV = "production";
        SECURE_COOKIES = "false"; # HTTP access via reverse proxy
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
      };
      # NVIDIA GPU access via CDI and security label disable
      podmanArgs = [
        "--device=nvidia.com/gpu=all"
        "--security-opt=label=disable"
      ];
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "10s";
      # ML model loading can take several minutes on first start
      TimeoutStartSec = "600";
    };

    unitConfig = {
      Description = "Scriberr AI Transcription Service";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
  };

  # Open firewall port for web interface
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
