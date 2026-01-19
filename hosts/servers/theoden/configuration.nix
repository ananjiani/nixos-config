# Theoden - k3s Server Node + Storage + CI/CD (Proxmox VM on rohan)
#
# Part of the k3s HA cluster (joins via boromir).
# Also serves as NFS storage server (migrated from faramir).
# Runs Attic binary cache and Buildbot-nix CI/CD.
{
  inputs,
  pkgs-stable,
  pkgs,
  config,
  lib,
  ...
}:

{
  imports = [
    ./disk-config.nix
    ./storage.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/k3s.nix
  ];

  networking = {
    hostName = "theoden";
    useDHCP = true;
    nameservers = [
      "192.168.1.1"
      "9.9.9.9"
    ]; # Router + Quad9 fallback (avoid chicken-and-egg with in-cluster DNS)
    firewall = {
      allowedTCPPorts = [
        111 # rpcbind/portmapper
        2049 # nfs
        20048 # mountd
        8080 # Attic binary cache
        8010 # Buildbot web UI
      ];
      allowedUDPPorts = [
        111 # rpcbind/portmapper
        2049 # nfs
        20048 # mountd
      ];
    };
  };

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      k3s_token = { };
      tailscale_authkey = { };
      # Attic binary cache
      attic_server_token_key = {
        owner = "atticd";
        group = "atticd";
        mode = "0400";
      };
      # Buildbot (Codeberg/Gitea)
      codeberg_token = {
        owner = "buildbot";
        mode = "0400";
      };
      codeberg_webhook_secret = {
        owner = "buildbot";
        mode = "0400";
      };
      codeberg_oauth_secret = {
        owner = "buildbot";
        mode = "0400";
      };
      buildbot_worker_password = {
        owner = "buildbot";
        mode = "0400";
      };
      # Cloudflare Tunnel
      cloudflared_tunnel_creds = {
        owner = "cloudflared";
        group = "cloudflared";
        mode = "0400";
      };
      # Attic push token for watch-store service
      attic_push_token = {
        owner = "root";
        mode = "0400";
      };
    };
  };

  # Custom modules configuration
  modules = {
    k3s = {
      enable = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://192.168.1.21:6443"; # boromir
      tokenFile = config.sops.secrets.k3s_token.path;
      extraFlags = [ "--node-ip=192.168.1.27" ]; # Force IPv4 for etcd cluster consistency
    };
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      exitNode = true;
      useExitNode = null; # Can't use exit node while being one
      subnetRoutes = [ "192.168.1.0/24" ];
      acceptDns = false; # Don't use Magic DNS (depends on in-cluster Headscale)
      acceptRoutes = false; # Don't accept subnet routes (we're already on the LAN)
    };
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

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

  services = {
    qemuGuest.enable = true;

    # NFS Server
    nfs.server = {
      enable = true;
      exports = ''
        /srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=0)
      '';
    };

    # PostgreSQL for Attic and Buildbot
    postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [
        "atticd"
        "buildbot"
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
      environmentFile = config.sops.secrets.attic_server_token_key.path;
      settings = {
        listen = "[::]:8080";
        database.url = "postgresql:///atticd?host=/run/postgresql";
        storage = {
          type = "local";
          path = "/var/lib/atticd/storage";
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
          default-retention-period = "3 months";
        };
      };
    };

    # Buildbot-nix CI/CD (Codeberg/Gitea)
    buildbot-nix.master = {
      enable = true;
      domain = "ci.dimensiondoor.xyz";
      useHTTPS = true; # Behind Cloudflare Tunnel
      authBackend = "gitea";
      workersFile = config.sops.secrets.buildbot_worker_password.path;
      buildSystems = [ "x86_64-linux" ];
      evalMaxMemorySize = 4096;
      evalWorkerCount = 4;
      gitea = {
        enable = true;
        instanceUrl = "https://codeberg.org";
        tokenFile = config.sops.secrets.codeberg_token.path;
        webhookSecretFile = config.sops.secrets.codeberg_webhook_secret.path;
        oauthId = "3c068786-8f5c-44b6-abe8-153394049c91";
        oauthSecretFile = config.sops.secrets.codeberg_oauth_secret.path;
        topic = "buildbot-nix";
      };
      admins = [ "ananjiani" ];
    };

    buildbot-nix.worker = {
      enable = true;
      workerPasswordFile = config.sops.secrets.buildbot_worker_password.path;
    };

    # Cloudflare Tunnel for Buildbot webhooks
    cloudflared = {
      enable = true;
      tunnels = {
        "b33ec739-7324-4c6f-b6fa-daedbe0828c8" = {
          credentialsFile = config.sops.secrets.cloudflared_tunnel_creds.path;
          default = "http_status:404";
          ingress = {
            "ci.dimensiondoor.xyz" = "http://localhost:8010";
          };
        };
      };
    };
  };

  # Attic watch-store: automatically push new store paths to binary cache
  systemd.services.attic-watch-store = {
    description = "Attic Watch Store - Push builds to binary cache";
    after = [
      "network.target"
      "atticd.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs-stable.attic-client ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";
    };
    script = ''
      # Configure Attic with the push token
      mkdir -p ~/.config/attic
      cat > ~/.config/attic/config.toml << EOF
      default-server = "local"

      [servers.local]
      endpoint = "http://localhost:8080"
      token = "$(cat ${config.sops.secrets.attic_push_token.path})"
      EOF
      chmod 600 ~/.config/attic/config.toml

      # Watch store and push new paths to middle-earth cache
      exec attic watch-store local:middle-earth
    '';
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
