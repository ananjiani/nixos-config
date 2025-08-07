# Home Assistant with voice assistants and smart home services
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.homeserver-home-assistant;
  haUser = "homeassistant";
  haGroup = "homeassistant";
in
{
  options.services.homeserver-home-assistant = {
    enable = lib.mkEnableOption "Home Assistant ecosystem";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Domain name for Home Assistant";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/storage2/homeassistant";
      description = "Configuration directory for Home Assistant";
    };

    ports = {
      homeassistant = lib.mkOption {
        type = lib.types.port;
        default = 8123;
        description = "Port for Home Assistant";
      };
      whisper = lib.mkOption {
        type = lib.types.port;
        default = 10300;
        description = "Port for Whisper STT";
      };
      piper = lib.mkOption {
        type = lib.types.port;
        default = 10200;
        description = "Port for Piper TTS";
      };
      openwakeword = lib.mkOption {
        type = lib.types.port;
        default = 10400;
        description = "Port for OpenWakeWord";
      };
      esphome = lib.mkOption {
        type = lib.types.port;
        default = 6052;
        description = "Port for ESPHome dashboard";
      };
      mosquitto = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "Port for Mosquitto MQTT";
      };
    };

    enableVoiceAssistant = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable voice assistant services (Whisper, Piper, OpenWakeWord)";
    };

    enableESPHome = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable ESPHome for ESP device management";
    };

    enableMatter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Matter server for smart home devices";
    };

    enableSignalCLI = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Signal CLI for notifications";
    };
  };

  config = lib.mkIf cfg.enable {
    # Services configuration
    services = {
      # Home Assistant service
      home-assistant = {
        enable = true;
        extraComponents = [
          # Core components
          "default_config"
          "esphome"
          "met"
          "radio_browser"

          # Voice/Assistant
          "assist_pipeline"
          "wake_word"
          "stt"
          "tts"
          "conversation"
          "intent"

          # Integrations
          "mqtt"
          "zha"
          "matter"
          "signal_messenger"

          # Media
          "cast"
          "spotify"
          "jellyfin"

          # Utility
          "backup"
          "mobile_app"
          "sun"
        ];

        config = {
          homeassistant = {
            name = "Home";
            unit_system = "metric";
            time_zone = "UTC"; # Change this to your timezone
            external_url = "https://${cfg.domain}";
            internal_url = "http://localhost:${toString cfg.ports.homeassistant}";
          };

          http = {
            server_port = cfg.ports.homeassistant;
            use_x_forwarded_for = true;
            trusted_proxies = [
              "127.0.0.1"
              "::1"
            ];
          };

          # MQTT for device communication
          mqtt = lib.mkIf (cfg.enableESPHome || cfg.enableMatter) {
            broker = "localhost";
            port = cfg.ports.mosquitto;
          };

          # Voice assistant configuration
          assist_pipeline = lib.mkIf cfg.enableVoiceAssistant { };

          # Frontend
          frontend = {
            themes = "!include_dir_merge_named themes";
          };

          # Automation
          automation = "!include automations.yaml";
          script = "!include scripts.yaml";
          scene = "!include scenes.yaml";
        };

        # Use SOPS for secrets
        configWritable = true;
        lovelaceConfigWritable = true;
      };

      # Mosquitto MQTT broker
      mosquitto = lib.mkIf (cfg.enableESPHome || cfg.enableMatter) {
        enable = true;
        listeners = [
          {
            port = cfg.ports.mosquitto;
            address = "0.0.0.0";
            settings = {
              allow_anonymous = false;
            };
            users = {
              homeassistant = {
                acl = [ "readwrite #" ];
                passwordFile =
                  if config.sops.secrets ? "homeassistant/mqtt_password" then
                    config.sops.secrets."homeassistant/mqtt_password".path
                  else
                    pkgs.writeText "mqtt-password" "CHANGE_ME_MQTT_PASSWORD";
              };
            };
          }
        ];
      };

      # Nginx reverse proxy - only if not local access
      nginx = lib.mkIf (cfg.domain != "homeassistant.local") {
        virtualHosts.${cfg.domain} = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://localhost:${toString cfg.ports.homeassistant}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
            '';
          };
        };

        # Add upgrade header for websockets
        appendHttpConfig = ''
          map $http_upgrade $connection_upgrade {
            default upgrade;
            "" close;
          }
        '';
      };
    };

    # Voice Assistant Services (using Docker for now)
    # TODO: Replace with native services when available
    virtualisation.oci-containers = {
      backend = "docker";
      containers = lib.mkMerge [
        (lib.mkIf cfg.enableVoiceAssistant {
          whisper = {
            image = "rhasspy/wyoming-whisper:latest";
            extraOptions = [ "--network=host" ];
            environment = {
              PUID = "1000";
              PGID = "1000";
            };
            cmd = [
              "--uri"
              "tcp://0.0.0.0:${toString cfg.ports.whisper}"
              "--model"
              "base"
              "--language"
              "en"
            ];
            volumes = [
              "${cfg.configDir}/whisper:/data"
            ];
          };

          piper = {
            image = "rhasspy/wyoming-piper:latest";
            extraOptions = [ "--network=host" ];
            environment = {
              PUID = "1000";
              PGID = "1000";
            };
            cmd = [
              "--uri"
              "tcp://0.0.0.0:${toString cfg.ports.piper}"
              "--voice"
              "en_US-lessac-medium"
            ];
            volumes = [
              "${cfg.configDir}/piper:/data"
            ];
          };

          openwakeword = {
            image = "rhasspy/wyoming-openwakeword:latest";
            extraOptions = [ "--network=host" ];
            environment = {
              PUID = "1000";
              PGID = "1000";
            };
            cmd = [
              "--uri"
              "tcp://0.0.0.0:${toString cfg.ports.openwakeword}"
              "--preload-model"
              "ok_nabu"
            ];
            volumes = [
              "${cfg.configDir}/openwakeword:/data"
              "${cfg.configDir}/openwakeword/custom:/custom"
            ];
          };
        })
        (lib.mkIf cfg.enableESPHome {
          esphome = {
            image = "ghcr.io/esphome/esphome:latest";
            extraOptions = [ "--network=host" ];
            environment = {
              PUID = "1000";
              PGID = "1000";
              USERNAME = "";
              PASSWORD = "";
            };
            volumes = [
              "${cfg.configDir}/esphome:/config"
            ];
          };
        })
        (lib.mkIf cfg.enableMatter {
          matter-server = {
            image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
            extraOptions = [ "--network=host" ];
            volumes = [
              "${cfg.configDir}/matter-server:/data"
              "/run/dbus:/run/dbus:ro"
            ];
          };
        })
        (lib.mkIf cfg.enableSignalCLI {
          signal-cli-rest-api = {
            image = "bbernhard/signal-cli-rest-api:latest";
            ports = [ "8080:8080" ];
            environment = {
              MODE = "json-rpc";
            };
            volumes = [
              "${cfg.configDir}/signal-cli:/home/.local/share/signal-cli"
            ];
          };
        })
      ];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts =
      with cfg.ports;
      [
        homeassistant
        mosquitto
      ]
      ++ lib.optionals cfg.enableESPHome [ esphome ]
      ++ lib.optionals cfg.enableVoiceAssistant [
        whisper
        piper
        openwakeword
      ];

    # Create directories
    systemd.tmpfiles.rules = [
      "d '${cfg.configDir}' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/whisper' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/piper' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/openwakeword' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/openwakeword/custom' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/esphome' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/matter-server' 0755 ${haUser} ${haGroup} -"
      "d '${cfg.configDir}/signal-cli' 0755 ${haUser} ${haGroup} -"
    ];

    # Create Home Assistant secrets.yaml file from SOPS
    systemd.services.homeassistant-secrets =
      lib.mkIf (config.sops.secrets ? "homeassistant/mqtt_password")
        {
          description = "Generate Home Assistant secrets.yaml";
          before = [ "home-assistant.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = haUser;
            Group = haGroup;
          };
          script = ''
            cat > ${cfg.configDir}/secrets.yaml <<EOF
            # Home Assistant secrets
            mqtt_password: "$(cat ${config.sops.secrets."homeassistant/mqtt_password".path})"
            signal_api_key: "$(cat ${config.sops.secrets."homeassistant/signal_api_key".path})"
            EOF
            chmod 600 ${cfg.configDir}/secrets.yaml
          '';
        };
  };
}
