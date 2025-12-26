# Zigbee2MQTT - Bridge between Zigbee devices and MQTT
#
# This module configures zigbee2mqtt to connect Zigbee devices to an MQTT broker.
# Home Assistant can then discover and control devices via MQTT auto-discovery.
{
  config,
  lib,
  ...
}:

let
  cfg = config.modules.zigbee2mqtt;
in
{
  options.modules.zigbee2mqtt = {
    enable = lib.mkEnableOption "zigbee2mqtt service";

    mqttServer = lib.mkOption {
      type = lib.types.str;
      default = "mqtt://localhost:1883";
      description = "MQTT broker URL";
    };

    serialPort = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyUSB0";
      description = "Serial port for Zigbee adapter (use /dev/serial/by-id/... for stability)";
    };

    frontendPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the zigbee2mqtt web frontend";
    };

    adapter = lib.mkOption {
      type = lib.types.enum [
        "zstack"
        "ember"
        "deconz"
        "zboss"
      ];
      default = "zstack";
      description = "Zigbee adapter type (zstack for CC2652/SONOFF, ember for EFR32)";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zigbee2mqtt";
      description = "Data directory for zigbee2mqtt";
    };
  };

  config = lib.mkIf cfg.enable {
    services.zigbee2mqtt = {
      enable = true;
      inherit (cfg) dataDir;

      settings = {
        # MQTT configuration
        mqtt = {
          server = cfg.mqttServer;
          base_topic = "zigbee2mqtt";
          include_device_information = true;
        };

        # Serial port configuration
        serial = {
          port = cfg.serialPort;
          inherit (cfg) adapter;
        };

        # Web frontend
        frontend = {
          port = cfg.frontendPort;
          host = "0.0.0.0";
        };

        # Home Assistant integration (auto-discovery enabled)
        homeassistant = {
          enabled = true;
        };

        # Advanced settings
        advanced = {
          # Network key - auto-generated on first run, back up from data dir
          network_key = "GENERATE";

          # Logging
          log_level = "info";
          log_output = [ "console" ];

          # Last seen timestamp format
          last_seen = "ISO_8601";

          # Transmit power (max for better range)
          transmit_power = 20;
        };

        # Device-specific configuration
        device_options = {
          legacy = false; # Use new-style entities
        };
      };
    };

    # Ensure zigbee2mqtt user can access serial ports
    users.users.zigbee2mqtt = {
      extraGroups = [ "dialout" ];
    };

    # Open firewall for frontend
    networking.firewall.allowedTCPPorts = [ cfg.frontendPort ];
  };
}
