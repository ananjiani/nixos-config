{
  pkgs,
  pkgs-stable,
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

  # Podman for container workloads (ComfyUI)
  virtualisation.podman.enable = true;

  # ComfyUI via Quadlet container (latest version for Flux.2 Klein support)
  # Using yanwk/comfyui-boot: CUDA 12.6, Python 3.12, includes ComfyUI Manager
  # Logs: journalctl -u comfyui.service
  virtualisation.quadlet.containers.comfyui = {
    containerConfig = {
      image = "docker.io/yanwk/comfyui-boot:cu126-cn";
      publishPorts = [ "8188:8188" ];
      volumes = [
        "/var/lib/comfyui/models:/app/ComfyUI/models"
        "/var/lib/comfyui/output:/app/ComfyUI/output"
        "/var/lib/comfyui/input:/app/ComfyUI/input"
        "/var/lib/comfyui/custom_nodes:/app/ComfyUI/custom_nodes"
      ];
      environments = {
        CLI_ARGS = "--listen 0.0.0.0";
      };
      podmanArgs = [ "--device=nvidia.com/gpu=all" ];
    };
  };
}
