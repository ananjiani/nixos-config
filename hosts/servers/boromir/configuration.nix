# Boromir - Proxmox VM (minimal base)
{
  inputs,
  pkgs-stable,
  config,
  ...
}:

{
  imports = [
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/nfs-client.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
  ];

  modules = {
    # Mount NFS share from theoden (use IP since we ARE the DNS server)
    nfs-client = {
      enable = true;
      server = "192.168.1.27";
    };

    # Tailscale client - this node is an exit node
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      exitNode = true;
    };

    # SSH server
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };

    # k3s cluster initializer (first server node)
    k3s = {
      enable = true;
      role = "server";
      clusterInit = true; # First node initializes the cluster
      tokenFile = config.sops.secrets.k3s_token.path;
    };
  };

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.k3s_token = { };
  };

  networking = {
    hostName = "boromir";
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

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
