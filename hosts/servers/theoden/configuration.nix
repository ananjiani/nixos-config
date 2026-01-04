# Theoden - k3s Server Node + Storage (Proxmox VM on rohan)
#
# Part of the k3s HA cluster (joins via boromir).
# Also serves as NFS storage server (migrated from faramir).
{
  inputs,
  pkgs-stable,
  config,
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
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
  ];

  networking = {
    hostName = "theoden";
    useDHCP = true;
  };

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.k3s_token = { };
    secrets.tailscale_authkey = { };
  };

  # Custom modules configuration
  modules = {
    # k3s server node (joins existing cluster)
    k3s = {
      enable = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://192.168.1.21:6443"; # boromir
      tokenFile = config.sops.secrets.k3s_token.path;
    };

    # Tailscale client - exit node through Mullvad
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      exitNode = true;
    };

    # SSH server
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
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
  boot = {
    loader.grub.enable = true;
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "virtio_net"
      "sd_mod"
    ];
  };

  # Add ammar to storage group for NFS write access
  users.users.ammar.extraGroups = [ "storage" ];

  # NFS Server (migrated from faramir)
  services.nfs.server = {
    enable = true;
    exports = ''
      /srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=0)
    '';
  };

  # Firewall: Allow NFS
  networking.firewall.allowedTCPPorts = [
    111 # rpcbind/portmapper
    2049 # nfs
    20048 # mountd
  ];
  networking.firewall.allowedUDPPorts = [
    111 # rpcbind/portmapper
    2049 # nfs
    20048 # mountd
  ];

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
