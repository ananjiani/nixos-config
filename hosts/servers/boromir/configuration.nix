# Boromir - Proxmox VM (minimal base)
{
  inputs,
  pkgs,
  pkgs-stable,
  config,
  ...
}:

{
  imports = [
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    inputs.comfyui-nix.nixosModules.default
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/nfs-client.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
    ../../../modules/nixos/nvidia.nix # GPU support for Ollama
    ../../../modules/nixos/server/attic-watch-store.nix
    ../../../modules/nixos/server/adguard.nix
    ./ai.nix
  ];

  modules = {
    # Mount NFS share from theoden (use IP since we ARE the DNS server)
    nfs-client = {
      enable = true;
      server = "192.168.1.27";
    };

    # Tailscale client - exit node + subnet router for remote access
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      exitNode = true;
      useExitNode = null; # Don't route through self (this IS the exit node)
      subnetRoutes = [ "192.168.1.0/24" ]; # Expose local network to Tailnet
      acceptDns = false; # Don't use Magic DNS (depends on in-cluster Headscale)
      acceptRoutes = false; # Don't accept subnet routes (we're already on the LAN)
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
      extraFlags = [ "--node-ip=192.168.1.21" ]; # Force IPv4 for etcd cluster consistency
    };
  };

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.k3s_token = { };
    secrets.tailscale_authkey = { };
  };

  # Docker for model conversion (bypasses NixOS library isolation)
  virtualisation.docker.enable = true;
  hardware.nvidia-container-toolkit.enable = true; # GPU passthrough for containers

  # nix-ld for running unpatched binaries (uvx, pip packages, etc.)
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++
      zlib
      curl
      openssl
    ];
  };

  networking = {
    hostName = "boromir";
    useDHCP = true;
    nameservers = [
      "192.168.1.1"
      "9.9.9.9"
    ]; # Router + Quad9 fallback (avoid chicken-and-egg with in-cluster DNS)
    firewall.allowedTCPPorts = [
      11434
      8188
    ]; # Ollama API + ComfyUI
  };

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Proxmox VM integration and Attic cache
  services = {
    qemuGuest.enable = true;
    attic-watch-store.enable = true;
  };

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

  # # Enable CUDA support for packages (needed for WhisperX with GPU acceleration)
  nixpkgs.config.cudaSupport = true;
}
