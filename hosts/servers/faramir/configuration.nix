# Faramir - NFS Server (Proxmox VM)
#
# Migrated from physical homeserver. Provides NFS storage to LAN.
# Storage: 3 passthrough disks with mergerfs + SnapRAID
{
  inputs,
  pkgs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ./disk-config.nix
    ./storage.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
  ];

  networking = {
    hostName = "faramir";
    useDHCP = true;
  };

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Proxmox VM integration
  services.qemuGuest.enable = true;

  # Boot configuration (GRUB for BIOS)
  # Note: disko sets grub.devices automatically from disk-config.nix
  boot = {
    loader.grub.enable = true;
    # Virtio modules for Proxmox
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "virtio_net"
      "sd_mod"
    ];
  };

  # NFS Server
  services.nfs.server = {
    enable = true;
    exports = ''
      /srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=0)
    '';
  };

  # Firewall: Allow NFS
  networking.firewall.allowedTCPPorts = [
    111    # rpcbind/portmapper
    2049   # nfs
    20048  # mountd
  ];
  networking.firewall.allowedUDPPorts = [
    111    # rpcbind/portmapper
    2049   # nfs
    20048  # mountd
  ];

  # Set initial password for ammar user (change after first login)
  users.users.ammar.initialPassword = "changeme";

  # Enable SSH module (permitRootLogin for nixos-anywhere deployment)
  modules.ssh = {
    enable = true;
    permitRootLogin = "prohibit-password";
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
