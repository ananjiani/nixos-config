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
    ../proxmox-disk-config.nix
    ../../profiles/server.nix
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/server/zigbee2mqtt.nix
  ];

  networking = {
    hostName = "samwise";
    firewall.allowedTCPPorts = [
      1883 # MQTT
    ];
  };

  modules = {
    adguard.enable = true;

    # k3s server node (joins existing cluster)
    k3s.podCidr = "10.42.2.0/24";

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
    };
  };

  services = {
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

  # USB/serial access for Zigbee dongle
  users.users.ammar.extraGroups = [ "dialout" ];
}
