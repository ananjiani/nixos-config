{
  pkgs,
  pkgs-stable,
  ...
}:
{
  # Model conversion tools (HuggingFace -> GGUF -> Ollama)
  environment.systemPackages =
    (with pkgs-stable; [
      llama-cpp # GGUF conversion and quantization
      (python3.withPackages (ps: [ ps.huggingface-hub ])) # Model downloads
    ])
    ++ [
      # Wrap whisperx to work around PyTorch 2.6+ weights_only=True default
      # pyannote-audio checkpoints use omegaconf objects not in safe globals
      # Also add omegaconf as runtime dep (missing in nixpkgs package)
      (pkgs.whisperx.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
          pkgs.python3Packages.omegaconf
        ];
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/whisperx \
            --set TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD true
        '';
      }))
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
}
