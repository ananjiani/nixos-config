# Theoden - k3s Server Node + Storage + CI/CD + Immich (Proxmox VM on rohan)
#
# Part of the k3s HA cluster (joins via boromir).
# Also serves as NFS storage server (migrated from faramir).
# Runs Attic binary cache, Buildbot-nix CI/CD, and Immich photo management.
# Immich ML offloaded to rohan (Proxmox host) with GPU acceleration.
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:

let
  inherit (inputs.buildbot-nix.lib) interpolate;

  # Deploy wrapper: runs after each successful nix-build in CI.
  # Only deploys server configs built on the main branch.
  sshConfig = pkgs.writeText "buildbot-ssh-config" ''
    Host *.lan 91.99.82.115
      StrictHostKeyChecking accept-new
      UserKnownHostsFile /var/lib/buildbot-worker/deploy-known-hosts
      IdentityFile /run/secrets/buildbot_deploy_ssh_key
      User root
      ConnectTimeout 30
      BatchMode yes
  '';

  deployScript = pkgs.writeShellScript "buildbot-deploy" ''
    set -euo pipefail

    if [ "$BRANCH" != "main" ]; then
      echo "Skipping deploy: not on main branch (branch=$BRANCH)"
      exit 0
    fi

    # Attr format is "x86_64-linux.nixos-<server>" — strip system prefix and "nixos-"
    STRIPPED=''${ATTR#*.}
    SERVER=''${STRIPPED#nixos-}
    case "$SERVER" in
      boromir|samwise|theoden|rivendell)
        HOST="$SERVER.lan"
        ;;
      erebor)
        HOST="91.99.82.115" # Hetzner public IP (matches deploy-rs config)
        ;;
      *)
        echo "Skipping deploy: $ATTR is not a server configuration"
        exit 0
        ;;
    esac

    if [ -z "$OUT_PATH" ]; then
      echo "No OUT_PATH set, cannot deploy"
      exit 1
    fi

    SSH_OPTS="-F ${sshConfig}"

    echo "Deploying $SERVER ($HOST) from $OUT_PATH..."

    # Copy the closure to the target host. --substitute-on-destination tells
    # the remote nix-daemon to fetch from its substituters first (Attic via
    # Cloudflare for erebor, theoden.lan direct for LAN servers), and only
    # ask us for what's missing — much cheaper than pushing everything.
    NIX_SSHOPTS="$SSH_OPTS" nix copy --substitute-on-destination --to "ssh://root@$HOST" "$OUT_PATH"

    # Activate: set system profile and switch
    ssh $SSH_OPTS "root@$HOST" \
      "nix-env -p /nix/var/nix/profiles/system --set '$OUT_PATH' && '$OUT_PATH/bin/switch-to-configuration' switch"

    echo "Deploy to $SERVER complete"
  '';

  # buildbot-prometheus: Exposes Buildbot metrics for Prometheus scraping.
  # Uses the same Python interpreter as buildbot-nix to ensure compatibility.
  buildbotPackages = config.services.buildbot-nix.packages;

  # Local patch for buildbot-nix: make mark_status_failed race-safe so an
  # obsolete storm can't abort the build-stop transaction and leak worker
  # slots (CI deadlock root cause, 2026-07-02). Stopgap pending upstream fix.
  patchedBuildbotNix = buildbotPackages.buildbot-nix.overrideAttrs (old: {
    src = pkgs.applyPatches {
      inherit (old) src;
      patches = [ ./patches/buildbot-nix-failed-status-upsert-race.patch ];
    };
  });

  buildbot-prometheus = buildbotPackages.python.pkgs.buildPythonPackage rec {
    pname = "buildbot-prometheus";
    version = "22.0.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/9f/88/dfddd9927138e0c49c6a88eb7f7a9d64de11ef1a9a78b91abaca175eb73c/buildbot_prometheus-22.0.0-py3-none-any.whl";
      hash = "sha256-sM95bktdQiwgQ8+GARWq/qXESrMrJQQ5E6YLyflqO0A=";
    };
    dependencies = with buildbotPackages.python.pkgs; [
      (toPythonModule buildbotPackages.buildbot)
      prometheus-client
      twisted
    ];
    doCheck = false;
  };
in
{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ./storage.nix
    ../../_profiles/server/configuration.nix
    ../../../modules/nixos/networking.nix
    inputs.quadlet-nix.nixosModules.quadlet
    ./romm.nix
    ./paperless.nix
    ./rclone-webdav.nix
  ];

  networking = {
    hostName = "theoden";
    firewall = {
      allowedTCPPorts = [
        111 # rpcbind/portmapper
        2049 # nfs
        20048 # mountd
        2283 # Immich
        8080 # Attic binary cache
        8010 # Buildbot web UI
        9101 # Buildbot Prometheus metrics
        445 # SMB
        139 # NetBIOS
        8384 # Syncthing web UI
        22000 # Syncthing sync protocol
        8085 # RomM web UI
        8086 # RetroArch WebDAV (Cloud Sync)
      ];
      allowedUDPPorts = [
        111 # rpcbind/portmapper
        2049 # nfs
        20048 # mountd
        137 # NetBIOS name service
        138 # NetBIOS datagram
        22000 # Syncthing device discovery (broadcast)
      ];
    };
  };

  # Custom modules configuration
  modules = {
    adguard.enable = true;

    # Additional vault-agent secrets (base.nix provides tailscale_authkey + attic_push_token,
    # k3s.nix provides k3s_token)
    vault-agent.secrets = {
      attic_server_token_key = {
        path = "secret/nixos/attic";
        field = "server_token_key";
        owner = "atticd";
        group = "atticd";
      };
      buildbot_worker_password = {
        path = "secret/nixos/buildbot";
        field = "worker_password";
        owner = "buildbot";
      };
      buildbot_worker_password_plain = {
        path = "secret/nixos/buildbot";
        field = "worker_password_plain";
        owner = "buildbot-worker";
      };
      buildbot_deploy_ssh_key = {
        path = "secret/nixos/buildbot";
        field = "deploy_ssh_key";
        owner = "buildbot-worker";
      };
      codeberg_token = {
        path = "secret/nixos/codeberg";
        field = "token";
        owner = "buildbot";
      };
      codeberg_webhook_secret = {
        path = "secret/nixos/codeberg";
        field = "webhook_secret";
        owner = "buildbot";
      };
      codeberg_oauth_secret = {
        path = "secret/nixos/codeberg";
        field = "oauth_secret";
        owner = "buildbot";
      };
      github_app_secret = {
        path = "secret/nixos/github";
        field = "app_secret";
        owner = "buildbot";
      };
      github_webhook_secret = {
        path = "secret/nixos/github";
        field = "webhook_secret";
        owner = "buildbot";
      };
      cloudflared_tunnel_creds = {
        path = "secret/nixos/cloudflared";
        field = "tunnel_creds";
        owner = "cloudflared";
        group = "cloudflared";
      };
      immich_secrets = {
        path = "secret/nixos/immich";
        field = "secrets";
        owner = "immich";
        group = "immich";
      };
      # Offsite backups (issue #41): B2 credentials + restic repo password.
      # S3-style var names: restic talks to B2 via its S3-compatible endpoint
      # because keys created after B2's v3 API cutover can't authorize
      # restic's native b2 backend (b2_authorize_account 400).
      b2_env = {
        path = "secret/nixos/backblaze";
        template = ''
          AWS_ACCESS_KEY_ID={{ with secret "secret/data/nixos/backblaze" }}{{ .Data.data.key_id }}{{ end }}
          AWS_SECRET_ACCESS_KEY={{ with secret "secret/data/nixos/backblaze" }}{{ .Data.data.application_key }}{{ end }}
        '';
      };
      restic_pw = {
        path = "secret/nixos/restic";
        field = "password";
      };
    };

    k3s = {
      enable = true;
      podCidr = "10.42.3.0/24";
    };

    # Keepalived for HA DNS - theoden is primary
    keepalived = {
      enable = true;
      priority = 100;
    };
  };

  # Pre-create service users so SOPS can set secret ownership during activation
  users = {
    users = {
      ammar.extraGroups = [ "storage" ];
      atticd = {
        isSystemUser = true;
        group = "atticd";
      };
      cloudflared = {
        isSystemUser = true;
        group = "cloudflared";
      };
    };
    groups = {
      atticd = { };
      cloudflared = { };
    };
  };

  # Theoden has extra node exporter collectors (textfile for Attic chunk checks)
  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=/var/lib/attic-monitor" ];
  };

  services = {
    # Prometheus postgres exporter for database metrics
    prometheus.exporters.postgres = {
      enable = true;
      port = 9187;
      openFirewall = true;
      runAsLocalSuperUser = true;
    };

    # Syncthing for game save sync (Desktop ↔ Deck ↔ theoden)
    syncthing = {
      enable = true;
      user = "ammar";
      group = "storage";
      dataDir = "/home/ammar/.syncthing";
      settings = {
        gui = {
          user = "ammar";
          password = ""; # No password on LAN, firewall-restricted
        };
        folders."game-saves" = {
          path = "/mnt/storage/games/saves";
          id = "game-saves";
          # Devices are paired via web UI (device IDs are per-install)
        };
      };
    };

    # NFS Server
    nfs.server = {
      enable = true;
      exports = ''
        /srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,insecure,fsid=0,anonuid=1500,anongid=1500)
      '';
    };

    # Samba file server (for Steam Deck and other clients)
    samba = {
      enable = true;
      openFirewall = false; # Already opened above with other ports
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "theoden";
          "netbios name" = "theoden";
          security = "user";
          "map to guest" = "never";
          "hosts allow" = "192.168.1. 100.64. 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
        };
        storage = {
          path = "/mnt/storage";
          browseable = "yes";
          "read only" = "no";
          "valid users" = "ammar";
          "force group" = "storage";
          "create mask" = "0664";
          "directory mask" = "2775";
        };
      };
    };

    # Samba Web Services Discovery (network browsing)
    samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    # Offsite backups to Backblaze B2 (issue #41). Credentials rendered by
    # vault-agent (b2_env + restic_pw). Separate repo path per dataset so
    # retention and restores are independent.
    restic.backups =
      let
        offsiteDefaults = {
          environmentFile = "/run/secrets/b2_env";
          passwordFile = "/run/secrets/restic_pw";
          initialize = true;
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 4"
            "--keep-monthly 6"
            "--keep-yearly 2"
          ];
        };
      in
      {
        postgres-offsite = offsiteDefaults // {
          repository = "s3:s3.us-east-005.backblazeb2.com/ammars-homelab-offsite/theoden/postgres";
          paths = [ "/var/backup/postgres" ];
          backupPrepareCommand = ''
            install -d -o postgres -g postgres -m 700 /var/backup/postgres
            ${pkgs.util-linux}/bin/runuser -u postgres -- ${config.services.postgresql.package}/bin/pg_dumpall -f /var/backup/postgres/all.sql
          '';
          timerConfig = {
            OnCalendar = "02:15";
            Persistent = true;
          };
        };
        immich-offsite = offsiteDefaults // {
          repository = "s3:s3.us-east-005.backblazeb2.com/ammars-homelab-offsite/theoden/immich";
          paths = [ "/srv/nfs/immich" ];
          timerConfig = {
            OnCalendar = "03:00";
            Persistent = true;
          };
        };
        game-saves-offsite = offsiteDefaults // {
          repository = "s3:s3.us-east-005.backblazeb2.com/ammars-homelab-offsite/theoden/game-saves";
          paths = [ "/mnt/storage/games/saves" ];
          timerConfig = {
            OnCalendar = "04:00";
            Persistent = true;
          };
        };
        romm-offsite = offsiteDefaults // {
          repository = "s3:s3.us-east-005.backblazeb2.com/ammars-homelab-offsite/theoden/romm";
          # assets = user-uploaded saves/states/screenshots; config = config.yml;
          # DB dump written by prepare command. resources/ (scraped artwork) and
          # the ROM library are re-derivable, so excluded.
          paths = [
            "/var/backup/romm"
            "/var/lib/romm/assets"
            "/var/lib/romm/config"
          ];
          # MYSQL_PWD comes from the container's own environment (romm-env),
          # so the password never appears in host argv.
          backupPrepareCommand = ''
            install -d -m 700 /var/backup/romm
            ${pkgs.podman}/bin/podman exec romm-db sh -c 'MYSQL_PWD=$MARIADB_PASSWORD exec mariadb-dump -u romm romm' > /var/backup/romm/romm.sql
          '';
          timerConfig = {
            OnCalendar = "04:30";
            Persistent = true;
          };
        };
        paperless-offsite = offsiteDefaults // {
          # Document media (the irreplacable part). Whoosh index and the
          # auto-generated secret_key in dataDir are re-derivable/regeneratable
          # and excluded. DB covered by postgres-offsite (pg_dumpall).
          repository = "s3:s3.us-east-005.backblazeb2.com/ammars-homelab-offsite/theoden/paperless";
          paths = [ "/srv/nfs/paperless/media" ];
          timerConfig = {
            OnCalendar = "05:00";
            Persistent = true;
          };
        };
      };

    # PostgreSQL for Attic and Buildbot
    postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [
        "atticd"
        "buildbot"
        "immich"
      ];
      ensureUsers = [
        {
          name = "atticd";
          ensureDBOwnership = true;
        }
        {
          name = "buildbot";
          ensureDBOwnership = true;
        }
        {
          name = "immich";
          ensureDBOwnership = true;
        }
      ];
      authentication = lib.mkForce ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     peer
        host    all             all             127.0.0.1/32            scram-sha-256
        host    all             all             ::1/128                 scram-sha-256
      '';
    };

    # Attic binary cache
    atticd = {
      enable = true;
      environmentFile = "/run/secrets/attic_server_token_key";
      settings = {
        listen = "[::]:8080";
        database.url = "postgresql:///atticd?host=/run/postgresql";
        storage = {
          type = "local";
          path = "/srv/nfs/attic";
        };
        chunking = {
          nar-size-threshold = 65536;
          min-size = 16384;
          avg-size = 65536;
          max-size = 262144;
        };
        compression.type = "zstd";
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "1 month";
        };
      };
    };

    # Buildbot-nix CI/CD (Codeberg/Gitea + GitHub)
    buildbot-nix.master = {
      enable = true;
      domain = "ci.dimensiondoor.xyz";
      useHTTPS = true; # Behind Cloudflare Tunnel
      authBackend = "gitea";
      workersFile = "/run/secrets/buildbot_worker_password";
      buildSystems = [ "x86_64-linux" ];
      evalMaxMemorySize = 4096;
      evalWorkerCount = 2;
      gitea = {
        enable = true;
        instanceUrl = "https://codeberg.org";
        tokenFile = "/run/secrets/codeberg_token";
        webhookSecretFile = "/run/secrets/codeberg_webhook_secret";
        oauthId = "3c068786-8f5c-44b6-abe8-153394049c91";
        oauthSecretFile = "/run/secrets/codeberg_oauth_secret";
        topic = "buildbot-nix";
      };
      github = {
        enable = true;
        appId = 2918119;
        appSecretKeyFile = "/run/secrets/github_app_secret";
        webhookSecretFile = "/run/secrets/github_webhook_secret";
        topic = "buildbot-nix";
      };
      admins = [ "ananjiani" ];
      # Disable GC root registration — buildbot builds are pushed to Attic
      # binary cache, so full closures don't need to be pinned on local disk.
      # The deploy post-build step runs immediately after nix build, before
      # any GC could run, so OUT_PATH is always available when needed.
      branches = {
        disable-gcroots = {
          matchGlob = "*";
          registerGCRoots = false;
        };
      };
      # Auto-deploy servers after successful builds on main
      postBuildSteps = [
        {
          name = "Deploy to server";
          environment = {
            BRANCH = interpolate "%(prop:branch)s";
            ATTR = interpolate "%(prop:attr)s";
            OUT_PATH = interpolate "%(prop:out_path)s";
          };
          command = [ (toString deployScript) ];
        }
      ];
    };

    buildbot-nix.worker = {
      enable = true;
      workerPasswordFile = "/run/secrets/buildbot_worker_password_plain";
    };

    # Buildbot Prometheus metrics exporter (port 9101, node_exporter uses 9100)
    # Override pythonPackages to inject buildbot-prometheus into buildbot-nix's
    # Python environment. buildbot-nix hardcodes this list so we must replicate
    # all original packages plus our addition.
    buildbot-master.pythonPackages = lib.mkForce (ps: [
      (ps.toPythonModule buildbotPackages.buildbot-worker)
      patchedBuildbotNix
      buildbotPackages.buildbot-effects
      buildbotPackages.buildbot-plugins.www
      buildbotPackages.buildbot-gitea
      buildbot-prometheus
    ]);
    buildbot-master.reporters = [ "reporters.Prometheus(port=9101)" ];

    # Cloudflare Tunnel for external access (webhooks, binary cache)
    cloudflared = {
      enable = true;
      tunnels = {
        "b33ec739-7324-4c6f-b6fa-daedbe0828c8" = {
          credentialsFile = "/run/secrets/cloudflared_tunnel_creds";
          default = "http_status:404";
          ingress = {
            "attic.dimensiondoor.xyz" = "http://localhost:8080";
            "ci.dimensiondoor.xyz" = "http://localhost:8010";
            "voicemail.dimensiondoor.xyz" = {
              service = "https://192.168.1.52";
              originRequest.noTLSVerify = true; # Internal traffic, skip cert validation
            };
          };
        };
      };
    };

    # Immich photo management
    # ML processing offloaded to rohan (GPU-accelerated via Podman)
    immich = {
      enable = true;
      port = 2283;
      host = "0.0.0.0";
      mediaLocation = "/srv/nfs/immich";
      database.createDB = false; # Using ensureDBOwnership above
      secretsFile = "/run/secrets/immich_secrets";
      settings = {
        machineLearning = {
          urls = [ "http://192.168.1.24:3003" ]; # rohan ML endpoint
        };
        oauth = {
          enabled = true;
          issuerUrl = "https://auth.dimensiondoor.xyz/application/o/immich/";
          clientId = "immich";
          clientSecret = "DB_SECRET:oauth_client_secret"; # From secretsFile
          scope = "openid email profile";
          buttonText = "Login with Authentik";
          autoRegister = true;
        };
        storageTemplate = {
          enabled = true;
          template = "{{y}}/{{MM}}/{{dd}}/{{filename}}";
        };
      };
    };
  };

  # Immich user needs storage group for NFS write access
  users.users.immich = {
    extraGroups = [ "storage" ];
  };

  # Attic chunk integrity check: detects DB records with missing chunk files on disk.
  # Runs daily and writes a Prometheus textfile metric picked up by node_exporter.
  systemd = {
    tmpfiles.rules = [
      "d /var/lib/attic-monitor 0755 atticd atticd -"
    ];

    # Services that consume vault-agent secrets must wait for rendering
    services = {
      restic-backups-postgres-offsite.after = [
        "vault-agent-default.service"
        "postgresql.service"
      ];
      restic-backups-immich-offsite.after = [ "vault-agent-default.service" ];
      restic-backups-game-saves-offsite.after = [ "vault-agent-default.service" ];
      restic-backups-romm-offsite.after = [
        "vault-agent-default.service"
        "romm-db.service"
      ];
      restic-backups-paperless-offsite.after = [ "vault-agent-default.service" ];

      # Restic backup for game saves (S3-ready via S3_REPO env var)
      restic-backup-game-saves = {
        description = "Restic backup for game saves";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.restic ];
        environment = {
          RESTIC_REPOSITORY = "/mnt/storage/games/.restic-saves";
          RESTIC_PASSWORD_FILE = "/dev/null"; # No encryption for LAN storage; swap for S3 key file when migrating
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "restic-backup-game-saves" ''
            set -euo pipefail
            REPO="''${S3_REPO:-$RESTIC_REPOSITORY}"
            if [ "$REPO" != "$RESTIC_REPOSITORY" ]; then
              echo "Using S3 repo: $REPO"
            fi
            exec ${pkgs.restic}/bin/restic backup /mnt/storage/games/saves \
              --repo "$REPO" \
              --insecure-no-password \
              --verbose
          '';
        };
      };

      # Restic retention (prune old snapshots)
      restic-forget-game-saves = {
        description = "Restic forget/prune for game saves";
        after = [ "restic-backup-game-saves.service" ];
        path = [ pkgs.restic ];
        environment = {
          RESTIC_REPOSITORY = "/mnt/storage/games/.restic-saves";
          RESTIC_PASSWORD_FILE = "/dev/null";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "restic-forget-game-saves" ''
            set -euo pipefail
            REPO="''${S3_REPO:-$RESTIC_REPOSITORY}"
            ${pkgs.restic}/bin/restic forget \
              --repo "$REPO" \
              --insecure-no-password \
              --keep-daily 30 \
              --prune \
              --verbose
          '';
        };
      };

      buildbot-master = {
        after = [ "vault-agent-default.service" ];
        wants = [ "vault-agent-default.service" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
      buildbot-worker = {
        after = [ "vault-agent-default.service" ];
        wants = [ "vault-agent-default.service" ];
      };
      atticd = {
        after = [ "vault-agent-default.service" ];
        wants = [ "vault-agent-default.service" ];
      };
      cloudflared-tunnel-b33ec739-7324-4c6f-b6fa-daedbe0828c8 = {
        after = [ "vault-agent-default.service" ];
        wants = [ "vault-agent-default.service" ];
      };
      immich-server = {
        after = [ "vault-agent-default.service" ];
        wants = [ "vault-agent-default.service" ];
      };

      attic-chunk-check = {
        description = "Check Attic binary cache chunk integrity";
        after = [
          "atticd.service"
          "postgresql.service"
        ];
        path = [
          config.services.postgresql.package
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "atticd";
        };
        script =
          let
            checkScript = pkgs.writeShellScript "attic-chunk-check" ''
              set -euo pipefail
              STORAGE_PATH="/srv/nfs/attic"
              OUTFILE="/var/lib/attic-monitor/attic.prom"
              DB_LIST=$(mktemp)
              FS_LIST=$(mktemp)
              trap 'rm -f "$DB_LIST" "$FS_LIST"' EXIT

              # All valid chunk filenames expected by DB (strip "local:" prefix, sort)
              psql -U atticd -d atticd -t -A \
                -c "SELECT remote_file_id FROM chunk WHERE state = 'V'" \
                | sed 's/^local://' | sort > "$DB_LIST"

              # All chunk files actually present on disk (just filename, sort)
              find "$STORAGE_PATH" -name '*.chunk' -printf '%f\n' | sort > "$FS_LIST"

              # Chunks in DB but missing on disk
              orphaned=$(comm -23 "$DB_LIST" "$FS_LIST" | wc -l)
              total=$(wc -l < "$DB_LIST")

              cat > "$OUTFILE" <<EOF
              # HELP attic_orphaned_chunks Chunk DB records with no corresponding file on disk
              # TYPE attic_orphaned_chunks gauge
              attic_orphaned_chunks $orphaned
              # HELP attic_chunks_total Total valid chunk records in Attic database
              # TYPE attic_chunks_total gauge
              attic_chunks_total $total
              EOF
            '';
          in
          "${checkScript}";
      };

      # buildbot-nix hardcodes GC root registration for the default branch
      # regardless of the registerGCRoots option (check_lookup short-circuits
      # on branch == default_branch). Periodically remove stale roots and GC
      # to prevent disk pressure from closure accumulation.
      buildbot-gcroots-cleanup = {
        description = "Remove buildbot GC roots and reclaim disk space";
        path = [
          pkgs.coreutils
          pkgs.findutils
          config.nix.package
        ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          set -euo pipefail
          GCROOTS_DIR=/nix/var/nix/gcroots/per-user/buildbot-worker
          if [ -d "$GCROOTS_DIR" ]; then
            echo "Removing buildbot GC roots under $GCROOTS_DIR"
            find "$GCROOTS_DIR" -type l -delete
            echo "GC roots removed, running nix-store --gc"
            nix-store --gc
          else
            echo "No buildbot GC roots directory found, skipping"
          fi
        '';
      };
    };

    timers = {
      restic-backup-game-saves = {
        description = "Run Restic backup for game saves daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };

      attic-chunk-check = {
        description = "Run Attic chunk integrity check daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          OnBootSec = "15min";
          RandomizedDelaySec = "1h";
        };
      };

      buildbot-gcroots-cleanup = {
        description = "Clean buildbot GC roots and reclaim disk daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          OnBootSec = "30min";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };
    };
  };
}
