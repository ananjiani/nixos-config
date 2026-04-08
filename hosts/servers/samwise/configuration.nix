# Samwise - Zigbee2MQTT and MQTT Broker (Proxmox VM on the-shire)
#
# This VM hosts:
# - Mosquitto MQTT broker (port 1883)
# - zigbee2mqtt with SONOFF Zigbee dongle (frontend on port 8080)
#
# Home Assistant (frodo) connects to Mosquitto for device control via MQTT.
{
  ...
}:

{
  imports = [
    ./disk-config.nix
    ../../profiles/server.nix
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/zigbee2mqtt.nix
    ../../../modules/nixos/server/k3s.nix
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

  modules = {
    # k3s server node (joins existing cluster)
    k3s = {
      enable = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://192.168.1.21:6443"; # boromir
      nodeIp = "192.168.1.26";
      podCidr = "10.42.2.0/24";
      flannelIface = "ens18"; # Prevent flannel from picking up keepalived VIPs
    };

    # Tailscale client - exit node + subnet router for remote access
    tailscale = {
      enable = true;
      exitNode = true;
      subnetRoutes = [ "192.168.1.0/24" ];
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

    # Keepalived for HA DNS - samwise is tertiary
    keepalived = {
      enable = true;
      priority = 80;
      unicastPeers = [
        "192.168.1.27" # theoden
        "192.168.1.21" # boromir
        "192.168.1.29" # rivendell
      ];
    };
  };

  services = {
    # Proxmox VM integration
    qemuGuest.enable = true;

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
}
