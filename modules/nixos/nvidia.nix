# NVIDIA GPU configuration module
{
  config,
  ...
}:

{
  # Add CUDA binary cache to speed up builds
  # See: https://wiki.nixos.org/wiki/CUDA
  nix.settings = {
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
  };
  # Enable NVIDIA proprietary drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  # Hardware configuration
  hardware = {
    # Enable hardware acceleration
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    # NVIDIA-specific settings
    nvidia = {
      # Modesetting is required for most Wayland compositors
      modesetting.enable = true;

      # Use proprietary drivers (better for RTX 3060)
      open = false;

      # Enable nvidia-persistenced for headless operation
      # Keeps GPUs initialized when no display is connected
      nvidiaPersistenced = true;

      # Optional: Enable power management (useful for servers)
      powerManagement.enable = false;

      # Optional: Fine-grained power management (not needed for desktop GPUs)
      powerManagement.finegrained = false;

      # Use stable driver for RTX 3060 (Ampere architecture)
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      nvidiaSettings = true;
    };

    # Enable NVIDIA Container Toolkit for Docker/container GPU support
    # Useful if you want to run WhisperX in containers
    nvidia-container-toolkit.enable = true;
  };

  # Load NVIDIA kernel modules at boot
  boot.initrd.kernelModules = [ "nvidia" ];
  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  # Optional: Set CUDA cache location
  environment.variables = {
    CUDA_CACHE_PATH = "/var/cache/cuda";
  };

  # Create CUDA cache directory
  systemd.tmpfiles.rules = [
    "d /var/cache/cuda 0755 root root -"
  ];
}
