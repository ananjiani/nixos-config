# Rivendell — HTPC (Trycoo WI6 N100 bare metal)
# Kodi-GBM media center with CEC remote, connected to LG OLED
{
  inputs,
  pkgs,
  pkgs-stable,
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

    # Tailscale — TEMPORARILY DISABLED for NIC stability testing
    # Tailscale modifies routing/netfilter and retries auth periodically;
    # testing whether this causes the ~12 min NIC death
    tailscale.enable = false;

    # k3s agent node — TEMPORARILY DISABLED for NIC stability testing
    # k3s iptables/nftables rules are suspected of causing NIC death at ~12 min
    # Re-enable once NIC stability is confirmed without k3s
    k3s.enable = false;

    # Keepalived for HA DNS — TEMPORARILY DISABLED for NIC stability testing
    # Re-enable once NIC stability is confirmed
    keepalived.enable = false;
  };

  # SOPS secrets
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # tailscale_authkey and k3s_token removed while services are disabled for NIC stability testing
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
  # This NIC loses inbound connectivity ~10-12 min after boot. Prometheus data across
  # 5 boots shows: rx_fifo=0 (no HW overflow), rx_err=0, carrier never drops, then
  # instant death (scrape 0.05s→10s timeout in one step). Thermal ruled out (54°C at
  # death vs 58°C survived for 69 min). k3s iptables ruled out (died without k3s).
  # Root cause: PCI runtime power management (D3hot) — separate from ASPM. The kernel
  # suspends idle PCI devices via /sys/devices/.../power/control=auto. The r8169 driver
  # supports runtime PM but PME wake from D3 is broken on many Realtek chips.
  # Four mitigations applied:
  # 1. pcie_aspm=off: disable PCIe link-level power states (see boot.kernelParams)
  # 2. PCI runtime PM: force power/control=on via udev to prevent D3 suspend
  # 3. ethtool: disable EEE (Energy Efficient Ethernet)
  # 4. ethtool: disable hardware offloading (rx/tx/sg/tso/gro/gso)
  # Two application methods (belt-and-suspenders):
  # - udev rule: fires on NIC/PCI add events (driver reload, interface cycling)
  # - systemd service: runs after network-addresses configures the interface,
  #   with PartOf to re-apply on every nixos-switch / deploy-rs activation
  # See: https://forum.proxmox.com/threads/lots-of-missed-packets-with-realtek-nic-r8168-r8169.168792/
  # See: https://bugs.archlinux.org/task/59090
  environment.systemPackages = [ pkgs.ethtool ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp1s0", RUN+="${pkgs.bash}/bin/bash -c '${pkgs.ethtool}/bin/ethtool --set-eee enp1s0 eee off; ${pkgs.ethtool}/bin/ethtool -K enp1s0 rx off tx off sg off tso off gro off gso off'"
    ACTION=="add", SUBSYSTEM=="pci", DRIVER=="r8169", ATTR{power/control}="on"
  '';
  systemd.services.nic-offloading = {
    description = "Disable hardware offloading on Realtek RTL8168 NIC";
    after = [ "network-addresses-enp1s0.service" ];
    requires = [ "network-addresses-enp1s0.service" ];
    wantedBy = [ "multi-user.target" ];
    # PartOf ensures this restarts whenever scripted networking restarts the
    # address service (e.g. during deploy-rs nixos-switch activations)
    partOf = [ "network-addresses-enp1s0.service" ];
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

  system.stateVersion = "25.11";
}
