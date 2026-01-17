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
      # Buildbot
      buildbot_github_app_secret_key = {
        owner = "buildbot";
        mode = "0400";
      };
      buildbot_github_webhook_secret = {
        owner = "buildbot";
        mode = "0400";
      };
      buildbot_github_oauth_id = {
        owner = "buildbot";
        mode = "0400";
      };
      buildbot_github_oauth_secret = {
        owner = "buildbot";
        mode = "0400";
      };
      buildbot_worker_password = {
        owner = "buildbot";
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
      subnetRoutes = [ "192.168.1.0/24" ];
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

  users.users.ammar.extraGroups = [ "storage" ];

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

    # Buildbot-nix CI/CD
    buildbot-nix.master = {
      enable = true;
      domain = "ci.theoden.lan";
      workersFile = config.sops.secrets.buildbot_worker_password.path;
      buildSystems = [ "x86_64-linux" ];
      evalMaxMemorySize = 4096;
      evalWorkerCount = 4;
      github = {
        # TODO: Replace with your GitHub App ID (integer)
        appId = 0;
        appSecretKeyFile = config.sops.secrets.buildbot_github_app_secret_key.path;
        webhookSecretFile = config.sops.secrets.buildbot_github_webhook_secret.path;
        oauthId = config.sops.secrets.buildbot_github_oauth_id.path;
        oauthSecretFile = config.sops.secrets.buildbot_github_oauth_secret.path;
        topic = "buildbot-nix";
      };
      admins = [ "ananjiani" ];
    };

    buildbot-nix.worker = {
      enable = true;
      workerPasswordFile = config.sops.secrets.buildbot_worker_password.path;
    };

    # Tailscale Funnel for GitHub webhooks
    tailscale.extraUpFlags = lib.mkAfter [ "--advertise-tags=tag:funnel" ];
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
