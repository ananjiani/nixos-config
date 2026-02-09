# PLACEHOLDER — REGENERATE on actual hardware with:
#   nixos-generate-config --show-hardware-config > hardware-configuration.nix
#
# This is a best-guess for the Trycoo WI6 (Intel N100, NVMe SSD, dual HDMI).
# Filesystem mounts WILL need to be updated after partitioning the real disk.

{
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot = {
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usb_storage"
      "sd_mod"
    ];
    kernelModules = [ "kvm-intel" ];
  };

  # Intel N100 GPU — i915 loaded automatically via initrd
  boot.initrd.kernelModules = [ "i915" ];

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = true;

  # TODO: Replace these with actual partitions after disk setup
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
