# Boromir - Proxmox VM (k3s server, exit node, AI workloads)
{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ./disk-config.nix
    ../../profiles/server.nix
    inputs.quadlet-nix.nixosModules.quadlet
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/nfs-client.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
    ../../../modules/nixos/nvidia.nix # GPU support for Ollama
    ../../../modules/nixos/server/adguard.nix
    ../../../modules/nixos/server/keepalived.nix
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
      authKeyFile = "/run/secrets/tailscale_authkey";
      exitNode = true;
      useExitNode = null; # Don't route through self (this IS the exit node)
      subnetRoutes = [ "192.168.1.0/24" ]; # Expose local network to Tailnet
      acceptDns = false; # Don't use Magic DNS (depends on in-cluster Headscale)
      acceptRoutes = false; # Don't accept subnet routes (we're already on the LAN)
    };

    # Keepalived for HA DNS - boromir is secondary
    keepalived = {
      enable = true;
      priority = 90;
      unicastPeers = [
        "192.168.1.27" # theoden
        "192.168.1.26" # samwise
        "192.168.1.29" # rivendell
      ];
    };

    # Additional vault-agent secret (base.nix provides tailscale_authkey + attic_push_token)
    vault-agent.secrets.k3s_token = {
      path = "secret/nixos/k3s";
      field = "token";
    };

    # k3s cluster initializer (first server node)
    k3s = {
      enable = true;
      role = "server";
      clusterInit = true; # First node initializes the cluster
      tokenFile = "/run/secrets/k3s_token";
      nodeIp = "192.168.1.21";
      podCidr = "10.42.1.0/24";
      flannelIface = "ens18"; # Prevent flannel from picking up keepalived VIPs
    };
  };

  # Keepalived notify scripts for Wyoming Whisper failover
  # These start/stop the wyoming-whisper service when VIP ownership changes
  # NOTE: Must use pkgs.bash for NixOS - /bin/bash doesn't exist
  environment.etc = {
    "keepalived/whisper-master.sh" = {
      mode = "0755";
      text = ''
        #!${pkgs.bash}/bin/bash
        logger "Keepalived WHISPER: Becoming MASTER - starting wyoming-whisper"
        systemctl start wyoming-whisper
      '';
    };
    "keepalived/whisper-backup.sh" = {
      mode = "0755";
      text = ''
        #!${pkgs.bash}/bin/bash
        logger "Keepalived WHISPER: Becoming BACKUP - stopping wyoming-whisper"
        systemctl stop wyoming-whisper
      '';
    };
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

  services = {
    # Proxmox VM integration
    qemuGuest.enable = true;

    # Second VRRP instance for Wyoming Whisper HA (alongside adguard_vip from module)
    # Rohan (192.168.1.24) is MASTER with priority 100
    # Boromir (this host) is BACKUP with priority 50
    keepalived.vrrpInstances.whisper_vip = {
      interface = "ens18";
      state = "BACKUP";
      virtualRouterId = 54;
      priority = 50;
      noPreempt = false;
      unicastPeers = [ "192.168.1.24" ]; # rohan
      virtualIps = [ { addr = "192.168.1.54/24"; } ];
      extraConfig = ''
        notify_master "/etc/keepalived/whisper-master.sh"
        notify_backup "/etc/keepalived/whisper-backup.sh"
        notify_fault "/etc/keepalived/whisper-backup.sh"
      '';
    };
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

  # Enable CUDA support for packages (needed for WhisperX with GPU acceleration)
  nixpkgs.config.cudaSupport = true;
}
