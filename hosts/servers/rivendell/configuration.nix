# Rivendell — HTPC (Trycoo WI6 N100 bare metal)
# Kodi-GBM media center with CEC remote, connected to LG OLED
{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../profiles/server.nix
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/htpc.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
    ../../../modules/nixos/server/adguard.nix
    ../../../modules/nixos/server/keepalived.nix
  ];

  modules = {
    # Kodi HTPC (greetd auto-login, ALSA audio, CEC, Intel graphics)
    htpc.enable = true;

    # Tailscale — PERMANENTLY DISABLED
    # Tailscale netfilter modifications trigger r8169 driver bug causing
    # complete inbound packet loss at ~11 min (see postmortem 2026-02-13)
    tailscale.enable = false;

    # Vault agent — DISABLED (can't reach OpenBao without Tailscale)
    vault-agent.enable = false;

    # k3s agent node — verified: iptables rules do NOT trigger r8169 NIC bug
    k3s = {
      enable = true;
      role = "agent";
      serverAddr = "https://192.168.1.21:6443"; # boromir
      tokenFile = config.sops.secrets.k3s_token.path;
      nodeIp = "192.168.1.29";
      podCidr = "10.42.0.0/24";
      flannelIface = "enp1s0"; # Prevent flannel from picking up keepalived VIPs
    };

    # Keepalived + AdGuard for HA DNS
    keepalived = {
      enable = true;
      interface = "enp1s0";
      priority = 70; # Lowest — prefer VMs (theoden=100, boromir=90, samwise=80)
      unicastPeers = [
        "192.168.1.27" # theoden
        "192.168.1.21" # boromir
        "192.168.1.26" # samwise
      ];
    };
  };

  # SOPS secrets — rivendell can't use vault-agent (no Tailscale → no OpenBao access)
  sops.secrets = {
    k3s_token = { };
    attic_push_token = { };
    trakt_client_id = {
      owner = "kodi";
      mode = "0400";
    };
    trakt_client_secret = {
      owner = "kodi";
      mode = "0400";
    };
  };

  # Attic watch-store: use SOPS token since vault-agent is disabled
  services.attic-watch-store.useSops = true;

  # Dendritic kodi module — inject Jacktook Trakt secrets
  # Debrid (TorBox) is handled by Comet Stremio addon, no API key needed here
  kodi.secrets = {
    traktClientId = config.sops.secrets.trakt_client_id.path;
    traktClientSecret = config.sops.secrets.trakt_client_secret.path;
  };

  networking.hostName = "rivendell";

  # Kodi HTPC user (server profile handles ammar via shared home.nix)
  home-manager.users.kodi = {
    imports = [ ./kodi-home.nix ];
  };

  # NFS client — required for Zot registry PVC (k8s NFS volume mount)
  # Enables rpcbind + nfs-utils userspace helpers so kubelet can mount NFS volumes
  boot.supportedFilesystems = [ "nfs" ];

  services = {
    rpcbind.enable = true;

    # Realtek RTL8168 (r8169 driver) NIC stability fixes — disable hw offloading
    # See: https://forum.proxmox.com/threads/lots-of-missed-packets-with-realtek-nic-r8168-r8169.168792/
    udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp1s0", RUN+="${pkgs.bash}/bin/bash -c '${pkgs.ethtool}/bin/ethtool --set-eee enp1s0 eee off; ${pkgs.ethtool}/bin/ethtool -K enp1s0 rx off tx off sg off tso off gro off gso off'"
      ACTION=="add", SUBSYSTEM=="pci", DRIVER=="r8169", ATTR{power/control}="on"
    '';
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
  # Two root causes identified (see postmortem 2026-02-13):
  # 1. Hardware offloading causes RX buffer overflow at ~7 min (256-entry max ring buffer)
  # 2. Tailscale netfilter modifications trigger driver bug at ~11 min (Tailscale disabled)
  # Mitigations:
  # - pcie_aspm=off: disable PCIe link-level power states (see boot.kernelParams)
  # - PCI runtime PM: force power/control=on via udev to prevent D3 suspend
  # - ethtool: disable EEE + all hardware offloading (rx/tx/sg/tso/gro/gso)
  environment.systemPackages = [ pkgs.ethtool ];
  systemd.services.nic-offloading = {
    description = "Disable hardware offloading on Realtek RTL8168 NIC";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.ethtool}/bin/ethtool --set-eee enp1s0 eee off
      ${pkgs.ethtool}/bin/ethtool -K enp1s0 rx off tx off sg off tso off gro off gso off
      # Disable PCI runtime PM (D3hot) — r8169 PME wake from D3 is broken
      pci_dev=$(basename $(readlink /sys/class/net/enp1s0/device))
      echo on > /sys/bus/pci/devices/$pci_dev/power/control
    '';
  };
}
