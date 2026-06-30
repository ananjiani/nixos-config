# RomM - self-hosted ROM manager (https://romm.app)
#
# Runs 3 Podman Quadlet containers: romm (web), mariadb (required since 3.0),
# redis (cache for background tasks).
#
# Library bind-mounted read-only from /mnt/storage/games/library.
# State in /var/lib/romm{,-db,-redis} (local disk, not the storage pool).
# Secrets rendered to /run/secrets/romm-env by vault-agent (Consul Template
# re-applies ownership on every lease renewal — not ExecStartPost).
#
# Exposed on :8085, fronted by k8s traefik at https://romm.lan (IngressRoute +
# manual Endpoints to 192.168.1.27, cert from the lan-ca ClusterIssuer).
#
# Logs: journalctl -u romm.service / romm-db.service / romm-redis.service
{ config, ... }:
let
  # env-file rendered by vault-agent from OpenBao secret/nixos/romm.
  # DB_PASSWD and MARIADB_PASSWORD share the db_passwd value so RomM and
  # mariadb agree on the user password.
  rommEnv = ''
    {{ with secret "secret/data/nixos/romm" }}
    DB_PASSWD={{ index .Data.data "db_passwd" }}
    MARIADB_PASSWORD={{ index .Data.data "db_passwd" }}
    ROMM_AUTH_SECRET_KEY={{ index .Data.data "auth_secret_key" }}
    SCREENSCRAPER_USER={{ index .Data.data "screenscraper_user" }}
    SCREENSCRAPER_PASSWORD={{ index .Data.data "screenscraper_password" }}
    STEAMGRIDDB_API_KEY={{ index .Data.data "steamgriddb_api_key" }}
    RETROACHIEVEMENTS_API_KEY={{ index .Data.data "retroachievements_api_key" }}
    IGDB_CLIENT_ID={{ index .Data.data "igdb_client_id" }}
    IGDB_CLIENT_SECRET={{ index .Data.data "igdb_client_secret" }}
    {{ end }}
  '';
in
{
  modules.vault-agent.secrets.romm-env = {
    path = "secret/nixos/romm";
    field = "db_passwd"; # ignored — template is set
    template = rommEnv;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/romm-db 0755 root root -"
    # redis runs as UID 999 inside the container (not root); the data dir
    # must be owned 999 so bgsave can fork+write temp-*.rdb. root:root 0755
    # causes 'Permission denied' on bgsave -> MISCONF -> login 500s.
    "d /var/lib/romm-redis 0755 999 999 -"
    "d /var/lib/romm 0755 root root -"
    "d /var/lib/romm/resources 0755 root root -"
    "d /var/lib/romm/assets 0755 root root -"
    "d /var/lib/romm/config 0755 root root -"
  ];

  virtualisation = {
    podman.enable = true;

    quadlet =
      let
        rommNet = config.virtualisation.quadlet.networks.romm.ref;
      in
      {
        # AdGuard binds 0.0.0.0:53 on theoden, which blocks podman's
        # aardvark-dns (wants <bridge-gateway>:53 for container name
        # resolution). Disabling podman DNS + pinning static IPs lets the
        # containers talk by IP without the :53 fight. External DNS still
        # works: containers inherit the host resolv.conf (192.168.1.53).
        # Proper fix for podman-on-theoden generically: bind AdGuard to
        # specific IPs instead of 0.0.0.0 — skipped, AdGuard is load-bearing.
        networks.romm.networkConfig = {
          subnets = [ "10.100.1.0/24" ];
          disableDns = true;
        };

        containers = {
          romm-db = {
            containerConfig = {
              image = "docker.io/library/mariadb:11";
              name = "romm-db";
              networks = [ rommNet ];
              ip = "10.100.1.10";
              environmentFiles = [ "/run/secrets/romm-env" ];
              environments = {
                MARIADB_RANDOM_ROOT_PASSWORD = "yes";
                MARIADB_DATABASE = "romm";
                MARIADB_USER = "romm";
              };
              volumes = [ "/var/lib/romm-db:/var/lib/mysql" ];
            };
            # /run/secrets/romm-env is wiped by sops-nix on every deploy and
            # re-rendered by vault-agent; order after it so the file exists.
            unitConfig = {
              After = [ "vault-agent-default.service" ];
              Wants = [ "vault-agent-default.service" ];
            };
          };

          romm-redis = {
            containerConfig = {
              image = "docker.io/library/redis:7";
              name = "romm-redis";
              networks = [ rommNet ];
              ip = "10.100.1.11";
              volumes = [ "/var/lib/romm-redis:/data" ];
              exec = "redis-server --appendonly yes";
            };
          };

          romm = {
            containerConfig = {
              image = "docker.io/rommapp/romm:latest";
              name = "romm";
              networks = [ rommNet ];
              ip = "10.100.1.12";
              publishPorts = [ "8085:8080" ];
              environmentFiles = [ "/run/secrets/romm-env" ];
              environments = {
                # IPs, not names — podman DNS is disabled on this net.
                DB_HOST = "10.100.1.10";
                DB_NAME = "romm";
                DB_USER = "romm";
                REDIS_HOST = "10.100.1.11";
                HASHEOUS_API_ENABLED = "true";
                HLTB_API_ENABLED = "true"; # HowLongToBeat — no key needed, free
              };
              volumes = [
                "/mnt/storage/games/library:/romm/library:ro"
                "/var/lib/romm/resources:/romm/resources"
                "/var/lib/romm/assets:/romm/assets"
                "/var/lib/romm/config:/romm/config"
              ];
            };
            # /run/secrets/romm-env is wiped by sops-nix on every deploy and
            # re-rendered by vault-agent; order after it so the file exists.
            unitConfig = {
              After = [ "vault-agent-default.service" ];
              Wants = [ "vault-agent-default.service" ];
            };
          };
        };
      };
  };
}
