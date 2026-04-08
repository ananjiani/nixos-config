# Hardware configuration for Hetzner Cloud CX22
#
# PLACEHOLDER: Replace with output of `nixos-generate-config --show-hardware-config`
# after provisioning the VPS. Hetzner cloud instances typically need:
# - virtio drivers for disk and network
# - KVM/QEMU guest support
_: {
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
    "sd_mod"
  ];
}
