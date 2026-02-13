# Hardware configuration for Rivendell (Trycoo WI6 N100 Mini PC)
# Generated from nixos-generate-config on live installer, then adapted for disko.
#
# Hardware: Intel Alder Lake-N (N100), 16GB DDR4, 512GB SATA SSD
# NIC: Realtek RTL8168 (r8169) — requires EEE/ASPM workarounds
# WiFi: Realtek RTL8822CE (unused, HTPC is wired)
# GPU: Intel UHD (Alder Lake-N, Gen12)
{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  nixpkgs.hostPlatform = "x86_64-linux";
}
