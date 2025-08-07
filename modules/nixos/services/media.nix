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

    # Media services configuration
    services = {
      # Jellyfin media server
      jellyfin = {
        enable = true;
        user = mediaUser;
        group = mediaGroup;
      };

      # Radarr (movies)
      radarr = {
        enable = true;
        user = mediaUser;
        group = mediaGroup;
        dataDir = "${cfg.configDir}/radarr";
      };

      # Sonarr (TV shows)
      sonarr = {
        enable = true;
        user = mediaUser;
        group = mediaGroup;
        dataDir = "${cfg.configDir}/sonarr";
      };

      # Prowlarr (indexer manager)
      prowlarr = {
        enable = true;
      };

      # Nginx reverse proxy - only for Jellyfin (public access)
      nginx.virtualHosts = lib.mkIf (cfg.domains.jellyfin != "jellyfin.local") {
        ${cfg.domains.jellyfin} = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://localhost:8096";
            proxyWebsockets = true;
          };
        };
      };
    };

    # qBittorrent will be configured with VPN in vpn-torrents.nix

    # Open firewall for local access to arr stack
    networking.firewall.allowedTCPPorts = [
      7878
      8989
      9696
      8096
    ];

    # TODO: Configure API keys once SOPS is set up
    # For now, API keys will need to be configured manually in each service
  };
}
