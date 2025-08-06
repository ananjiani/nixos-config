# Media services: Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent
{ config, lib, ... }:

let
  cfg = config.services.homeserver-media;
  mediaUser = "media";
  mediaGroup = "media";
in
{
  options.services.homeserver-media = {
    enable = lib.mkEnableOption "media services";

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/storage2/arr-data/media";
      description = "Directory for media files";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/storage2/arr-data/config";
      description = "Directory for service configurations";
    };

    domains = {
      jellyfin = lib.mkOption {
        type = lib.types.str;
        description = "Domain for Jellyfin";
      };
      radarr = lib.mkOption {
        type = lib.types.str;
        description = "Domain for Radarr";
      };
      sonarr = lib.mkOption {
        type = lib.types.str;
        description = "Domain for Sonarr";
      };
      prowlarr = lib.mkOption {
        type = lib.types.str;
        description = "Domain for Prowlarr";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Create media user and group
    users.users.${mediaUser} = {
      isSystemUser = true;
      group = mediaGroup;
      uid = 1000; # Match your current setup
    };
    users.groups.${mediaGroup} = {
      gid = 1000; # Match your current setup
    };

    # Jellyfin media server
    services.jellyfin = {
      enable = true;
      user = mediaUser;
      group = mediaGroup;
    };

    # Radarr (movies)
    services.radarr = {
      enable = true;
      user = mediaUser;
      group = mediaGroup;
      dataDir = "${cfg.configDir}/radarr";
    };

    # Sonarr (TV shows)
    services.sonarr = {
      enable = true;
      user = mediaUser;
      group = mediaGroup;
      dataDir = "${cfg.configDir}/sonarr";
    };

    # Prowlarr (indexer manager)
    services.prowlarr = {
      enable = true;
    };

    # qBittorrent will be configured with VPN in vpn-torrents.nix

    # Nginx reverse proxies
    services.nginx.virtualHosts = {
      ${cfg.domains.jellyfin} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:8096";
          proxyWebsockets = true;
        };
      };

      ${cfg.domains.radarr} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:7878";
        };
      };

      ${cfg.domains.sonarr} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:8989";
        };
      };

      ${cfg.domains.prowlarr} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:9696";
        };
      };
    };

    # SOPS secrets for API keys
    sops.secrets = {
      "arr_stack/radarr_api_key" = {
        owner = mediaUser;
      };
      "arr_stack/sonarr_api_key" = {
        owner = mediaUser;
      };
      "arr_stack/prowlarr_api_key" = {
        owner = mediaUser;
      };
    };
  };
}
