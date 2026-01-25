{
  pkgs,
  pkgs-stable,
  lib,
  ...
}:
let
  # Wrapper for whisperx that sets LD_LIBRARY_PATH for PyTorch
  # uvx downloads pre-built wheels that need system libraries + CUDA
  # TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD: pyannote checkpoints use omegaconf objects
  whisperx-wrapper = pkgs.writeShellScriptBin "whisperx" ''
    export LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/current-system/sw/share/nix-ld/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1
    exec ${pkgs.uv}/bin/uvx whisperx "$@"
  '';
in
{
  # Model conversion tools (HuggingFace -> GGUF -> Ollama)
  # WhisperX: use uvx with wrapper (nixpkgs broken: pyannote-audio 4.0)
  # See: https://github.com/NixOS/nixpkgs/issues/460172
  environment.systemPackages = with pkgs-stable; [
    llama-cpp # GGUF conversion and quantization
    (python3.withPackages (ps: [ ps.huggingface-hub ])) # Model downloads
    pkgs.uv # For ad-hoc Python tools
    whisperx-wrapper
  ];

  # Ollama LLM service with GPU acceleration
  services.ollama = {
    enable = true;
    host = "0.0.0.0"; # Allow access from k8s pods
    port = 11434;
    package = pkgs-stable.ollama-cuda; # CUDA-accelerated package (stable for cache hits)
    loadModels = [
      "qwen3:8b"
      "qwen3:0.6b"
      "qwen3-vl:8b" # Vision-language model for image understanding
      "nomic-embed-text" # GPU-accelerated embeddings for Open WebUI
      "deepseek-r1:8b-0528-qwen3-q4_K_M" # Reasoning model with tool support
    ];
  };

  # Podman for container workloads
  virtualisation = {
    podman.enable = true;

    quadlet.containers = {
      # ComfyUI via Quadlet container (latest version for Flux.2 Klein support)
      # Using yanwk/comfyui-boot: CUDA 12.6, Python 3.12, includes ComfyUI Manager
      # Logs: journalctl -u comfyui.service
      comfyui = {
        containerConfig = {
          image = "docker.io/yanwk/comfyui-boot:cu126-slim";
          publishPorts = [ "8188:8188" ];
          volumes = [
            # Container state (ComfyUI installation, custom_nodes, etc.)
            "/var/lib/comfyui/storage:/root"
            # Models - mounted after /root so it overlays the models dir
            "/var/lib/comfyui/models:/root/ComfyUI/models"
            # User content
            "/var/lib/comfyui/input:/root/ComfyUI/input"
            "/var/lib/comfyui/output:/root/ComfyUI/output"
          ];
          environments = {
            CLI_ARGS = "--listen 0.0.0.0";
          };
          podmanArgs = [ "--device=nvidia.com/gpu=all" ];
        };
      };

      # Wyoming Faster Whisper for voicemail transcription (Keepalived BACKUP)
      # Primary runs on rohan; this instance is on-demand via Keepalived failover.
      # Logs: journalctl -u wyoming-whisper.service
      wyoming-whisper = {
        containerConfig = {
          image = "docker.io/rhasspy/wyoming-whisper:latest";
          publishPorts = [ "10300:10300" ];
          volumes = [ "/var/lib/wyoming-whisper:/data" ];
          podmanArgs = [ "--device=nvidia.com/gpu=all" ];
          exec = "--model medium --language en --uri tcp://0.0.0.0:10300 --data-dir /data --download-dir /data";
        };
      };
    };
  };

  # Disable auto-start - Keepalived notify scripts manage this service
  systemd.services.wyoming-whisper.wantedBy = lib.mkForce [ ];

  # Data directory for whisper models
  systemd.tmpfiles.rules = [
    "d /var/lib/wyoming-whisper 0755 root root -"
  ];

  # Firewall - allow Wyoming protocol
  networking.firewall.allowedTCPPorts = [ 10300 ];
}
