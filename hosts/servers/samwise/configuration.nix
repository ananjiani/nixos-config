# Samwise - Zigbee2MQTT and MQTT Broker (Proxmox VM on the-shire)
#
# This VM hosts:
# - Mosquitto MQTT broker (port 1883)
# - zigbee2mqtt with SONOFF Zigbee dongle (frontend on port 8080)
#
# Home Assistant (frodo) connects to Mosquitto for device control via MQTT.
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
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/zigbee2mqtt.nix
    ../../../modules/nixos/server/k3s.nix
    ../../../modules/nixos/server/attic-watch-store.nix
    ../../../modules/nixos/server/adguard.nix
    ../../../modules/nixos/server/keepalived.nix
  ];

  networking = {
    hostName = "samwise";
    useDHCP = true;
    nameservers = [
      "192.168.1.1"
      "9.9.9.9"
    ]; # Router + Quad9 fallback (avoid chicken-and-egg with in-cluster DNS)
    firewall.allowedTCPPorts = [
      1883 # MQTT
    ];
  };

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.k3s_token = { };
    secrets.tailscale_authkey = { };
  };

  modules = {
    # k3s server node (joins existing cluster)
    k3s = {
      enable = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://192.168.1.21:6443"; # boromir
      tokenFile = config.sops.secrets.k3s_token.path;
      extraFlags = [ "--node-ip=192.168.1.26" ]; # Force IPv4 for etcd cluster consistency
    };

    # Tailscale client - exit node + subnet router for remote access
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      exitNode = true;
      useExitNode = null; # Can't use exit node while being one
      subnetRoutes = [ "192.168.1.0/24" ]; # Expose local network to Tailnet
      acceptDns = false; # Don't use Magic DNS (depends on in-cluster Headscale)
      acceptRoutes = false; # Don't accept subnet routes (we're already on the LAN)
    };

    # Zigbee2MQTT configuration
    zigbee2mqtt = {
      enable = true;
      mqttServer = "mqtt://localhost:1883";
      frontendPort = 8080;
      # USB device path - verify with: ls -la /dev/serial/by-id/
      serialPort = "/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20230605144345-if00";
      adapter = "ember"; # For SONOFF ZBDongle-E (V2) with EFR32MG21
    };

    # SSH server
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };

    # Keepalived for HA DNS - samwise is tertiary
    keepalived = {
      enable = true;
      priority = 80;
      unicastPeers = [
        "192.168.1.27" # theoden
        "192.168.1.21" # boromir
      ];
    };
  };

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  services = {
    # Proxmox VM integration and Attic cache
    qemuGuest.enable = true;
    attic-watch-store.enable = true;

    # Prometheus node exporter for VM-level monitoring
    prometheus.exporters.node = {
      enable = true;
      port = 9100;
      openFirewall = true;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };

    # Prometheus MQTT exporter for Mosquitto metrics
    # TODO: Re-enable when Zigbee devices are added to the network
    prometheus.exporters.mqtt = {
      enable = false;
      openFirewall = true;
    };

    # Mosquitto MQTT broker
    mosquitto = {
      enable = true;
      listeners = [
        {
          port = 1883;
          address = "0.0.0.0";
          settings = {
            allow_anonymous = true; # For initial setup; add auth later
          };
          acl = [ "topic readwrite #" ];
        }
      ];
    };
  };

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

  # USB/serial access for Zigbee dongle
  users.users.ammar.extraGroups = [ "dialout" ];

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
