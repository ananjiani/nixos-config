# Boromir - Proxmox VM (k3s server, exit node, AI workloads)
{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ../../_profiles/server/configuration.nix
    inputs.quadlet-nix.nixosModules.quadlet
    ../../../modules/nixos/nfs-client.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/nvidia.nix # GPU support for Ollama
    ./ai.nix
  ];

  modules = {
    nfs-client = {
      enable = true;
      server = "192.168.1.27"; # theoden (use IP since we ARE the DNS server)
    };

    adguard.enable = true;

    # Keepalived for HA DNS - boromir is secondary
    keepalived = {
      enable = true;
      priority = 90;
    };

    # k3s cluster initializer (first server node)
    k3s = {
      enable = true;
      clusterInit = true;
      podCidr = "10.42.1.0/24";
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
    firewall.allowedTCPPorts = [
      11434
      8188
    ]; # Ollama API + ComfyUI
  };

  services = {
    # Health check for the Whisper VIP: the local wyoming-whisper must accept
    # Wyoming connections, otherwise this host must not advertise 192.168.1.54.
    # weight 0 => a failing check forces FAULT and releases the VIP.
    keepalived.vrrpScripts.check_whisper = {
      script = "${pkgs.netcat-openbsd}/bin/nc -z -w 2 127.0.0.1 10300";
      interval = 5;
      fall = 3;
      rise = 2;
      timeout = 3;
      weight = 0;
      user = "keepalived_script";
      group = "keepalived_script";
    };

    # Second VRRP instance for Wyoming Whisper HA (alongside adguard_vip from module)
    # Rohan (192.168.1.24) is MASTER with priority 100
    # Boromir (this host) is BACKUP with priority 50
    # wyoming-whisper runs unconditionally here (see ai.nix); the VIP follows the
    # service, not the other way round.
    keepalived.vrrpInstances.whisper_vip = {
      interface = "ens18";
      state = "BACKUP";
      virtualRouterId = 54;
      priority = 50;
      noPreempt = false;
      unicastPeers = [ "192.168.1.24" ]; # rohan
      virtualIps = [ { addr = "192.168.1.54/24"; } ];
      trackScripts = [ "check_whisper" ];
    };
  };

  # Enable CUDA support for packages (needed for WhisperX with GPU acceleration)
  nixpkgs.config.cudaSupport = true;
}
