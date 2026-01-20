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
      pkgs.whisperx # Uses pkgs (not pkgs-stable) to get CUDA support from nixpkgs.config.cudaSupport
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
