# NVIDIA GPU configuration module
{
  config,
  ...
}:

{
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

      # Use proprietary drivers (better for GTX 1070 Ti)
      open = false;

      # Enable nvidia-persistenced for headless operation
      # Keeps GPUs initialized when no display is connected
      # nvidiaPersistenced = true;

      # Optional: Enable power management (useful for servers)
      powerManagement.enable = false;

      # Optional: Fine-grained power management (not needed for desktop GPUs)
      powerManagement.finegrained = false;

      # Use legacy_535 driver for GTX 1070 Ti (Pascal) - better CUDA compatibility
      # legacy_535 causes "unsupported display driver / cuda driver combination" errors
      package = config.boot.kernelPackages.nvidiaPackages.legacy_535;
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
