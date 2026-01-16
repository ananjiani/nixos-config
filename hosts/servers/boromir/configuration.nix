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
    ../../../modules/nixos/nvidia.nix # GPU support for Ollama
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
      subnetRoutes = [ "192.168.1.0/24" ]; # Expose local network to Tailnet
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
    secrets.tailscale_authkey = { };
  };

  # Model conversion tools (HuggingFace -> GGUF -> Ollama)
  environment.systemPackages = with pkgs-stable; [
    llama-cpp # GGUF conversion and quantization
    (python3.withPackages (ps: [ ps.huggingface-hub ])) # Model downloads
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
      "mlmlml" # Marxist-Leninist educator model
      "nomic-embed-text" # GPU-accelerated embeddings for Open WebUI
    ];
  };

  # Docker for model conversion (bypasses NixOS library isolation)
  virtualisation.docker = {
    enable = true;
    enableNvidia = true; # GPU passthrough for containers
  };

  networking = {
    hostName = "boromir";
    useDHCP = true;
    firewall.allowedTCPPorts = [ 11434 ]; # Ollama API
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
