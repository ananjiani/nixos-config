{
  pkgs,
  pkgs-stable,
  inputs,
  ...
}:
let
  # Pinned nixpkgs with pyannote-audio 3.4.0 (before 4.0 broke whisperx)
  pkgs-whisperx = import inputs.nixpkgs-whisperx {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
in
{
  # Model conversion tools (HuggingFace -> GGUF -> Ollama)
  environment.systemPackages =
    (with pkgs-stable; [
      llama-cpp # GGUF conversion and quantization
      (python3.withPackages (ps: [ ps.huggingface-hub ])) # Model downloads
    ])
    ++ [
      # Use pinned whisperx from before pyannote-audio 4.0 broke compatibility
      # See: https://github.com/NixOS/nixpkgs/issues/460172
      # Wrap to work around PyTorch 2.6+ weights_only=True default
      (pkgs-whisperx.whisperx.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
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
