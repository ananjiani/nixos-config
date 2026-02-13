# Rivendell — HTPC (Trycoo WI6 N100 bare metal)
# Kodi-GBM media center with CEC remote, connected to LG OLED
{
  inputs,
  pkgs,
  pkgs-stable,
  config,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/htpc.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
    ../../../modules/nixos/server/adguard.nix
    ../../../modules/nixos/server/keepalived.nix
  ];

  modules = {
    # Kodi HTPC (greetd auto-login, ALSA audio, CEC, Intel graphics)
    htpc.enable = true;

    # SSH for remote maintenance
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };

    # Tailscale for remote access via Headscale
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      useExitNode = null; # HTPC needs direct LAN access, no exit node
    };

    # k3s agent node (joins existing cluster, no control plane overhead)
    k3s = {
      enable = true;
      role = "agent";
      serverAddr = "https://192.168.1.21:6443"; # boromir
      tokenFile = config.sops.secrets.k3s_token.path;
      extraFlags = [ "--node-ip=192.168.1.29" ];
    };

    # Keepalived for HA DNS — rivendell is quaternary (lowest priority, may power cycle)
    keepalived = {
      enable = true;
      interface = "enp1s0"; # Bare metal NIC (not ens18 like Proxmox VMs)
      priority = 70;
      unicastPeers = [
        "192.168.1.27" # theoden
        "192.168.1.21" # boromir
        "192.168.1.26" # samwise
      ];
    };
  };

  # SOPS secrets
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.tailscale_authkey = { };
    secrets.k3s_token = { };
  };

  networking = {
    hostName = "rivendell";
    useDHCP = false;
    interfaces.enp1s0.ipv4.addresses = [
      {
        address = "192.168.1.29";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.1.1";
    nameservers = [
      "192.168.1.53" # AdGuard Home VIP
      "9.9.9.9" # Quad9 fallback
    ];
  };

  # Home Manager for ammar (SSH maintenance user)
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Prometheus node exporter for monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };

  # Boot configuration (bare metal EFI)
  # Hardware kernel modules are in hardware-configuration.nix
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.kernelModules = [ "i915" ]; # Intel GPU early load for Kodi-GBM
    # Disable PCIe Active State Power Management — ASPM puts the Realtek
    # RTL8168 PCI device into low-power states that cause the NIC to stop
    # responding to inbound traffic. EEE alone is not sufficient.
    kernelParams = [ "pcie_aspm=off" ];
  };

  # Realtek RTL8168 (r8169 driver) NIC stability fixes:
  # This NIC drops inbound connectivity intermittently due to aggressive
  # power management. Three mitigations applied (belt-and-suspenders):
  # 1. r8169 module param: disable EEE at driver load time (before NIC is up)
  # 2. pcie_aspm=off: disable PCIe power management at bus level (see boot.kernelParams)
  # 3. ethtool: runtime EEE disable as a fallback
  # See: https://gist.github.com/milesburton/c079ab7397d439ccb59e06b9f1ddce16
  boot.extraModprobeConfig = "options r8169 eee_enable=0";
  environment.systemPackages = [ pkgs.ethtool ];
  systemd.services.disable-eee = {
    description = "Disable EEE on Realtek NIC (runtime fallback)";
    after = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-eee enp1s0 eee off";
    };
  };

  system.stateVersion = "25.11";
}
