# Rivendell — HTPC (Trycoo WI6 N100 bare metal)
# Kodi-GBM media center with CEC remote, connected to LG OLED
{
  config,
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
    secrets = {
      trakt_client_id = {
        owner = "kodi";
        mode = "0400";
      };
      trakt_client_secret = {
        owner = "kodi";
        mode = "0400";
      };
    };
  };

  # Dendritic kodi module — inject Jacktook Trakt secrets
  # Debrid (TorBox) is handled by Comet Stremio addon, no API key needed here
  kodi.secrets = {
    traktClientId = config.sops.secrets.trakt_client_id.path;
    traktClientSecret = config.sops.secrets.trakt_client_secret.path;
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

  # Home Manager
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix; # SSH maintenance user
    users.kodi = {
      imports = [ ./kodi-home.nix ];
    }; # Kodi HTPC (advancedsettings.xml)
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
  # Two root causes identified (see postmortem 2026-02-13):
  # 1. Hardware offloading causes RX buffer overflow at ~7 min (256-entry max ring buffer)
  # 2. Tailscale netfilter modifications trigger driver bug at ~11 min (Tailscale disabled)
  # Mitigations:
  # - pcie_aspm=off: disable PCIe link-level power states (see boot.kernelParams)
  # - PCI runtime PM: force power/control=on via udev to prevent D3 suspend
  # - ethtool: disable EEE + all hardware offloading (rx/tx/sg/tso/gro/gso)
  # See: https://forum.proxmox.com/threads/lots-of-missed-packets-with-realtek-nic-r8168-r8169.168792/
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
