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
    Host *.lan
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
      boromir|samwise|theoden|rivendell) ;;
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
    HOST="$SERVER.lan"

    echo "Deploying $SERVER from $OUT_PATH..."

    # Copy the closure to the target host
    NIX_SSHOPTS="$SSH_OPTS" nix copy --to "ssh://root@$HOST" "$OUT_PATH"

    # Activate: set system profile and switch
    ssh $SSH_OPTS "root@$HOST" \
      "nix-env -p /nix/var/nix/profiles/system --set '$OUT_PATH' && '$OUT_PATH/bin/switch-to-configuration' switch"

    echo "Deploy to $SERVER complete"
  '';

  # buildbot-prometheus: Exposes Buildbot metrics for Prometheus scraping.
  # Uses the same Python interpreter as buildbot-nix to ensure compatibility.
  buildbotPackages = config.services.buildbot-nix.packages;
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
    ../proxmox-disk-config.nix
    ./storage.nix
    ../../profiles/server.nix
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/server/k3s.nix
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
      ];
      allowedUDPPorts = [
        111 # rpcbind/portmapper
        2049 # nfs
        20048 # mountd
        137 # NetBIOS name service
        138 # NetBIOS datagram
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
    };

    k3s = {
      enable = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://192.168.1.21:6443"; # boromir
      nodeIp = "192.168.1.27";
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
          warnOnly = true;
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
      buildbotPackages.buildbot-nix
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
      buildbot-master = {
        after = [ "vault-agent-default.service" ];
        wants = [ "vault-agent-default.service" ];
      };
      buildbot-worker = {
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
    };

    timers.attic-chunk-check = {
      description = "Run Attic chunk integrity check daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        OnBootSec = "15min";
        RandomizedDelaySec = "1h";
      };
    };
  };
}
