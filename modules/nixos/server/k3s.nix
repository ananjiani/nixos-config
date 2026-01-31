# k3s - Lightweight Kubernetes
#
# This module configures k3s for an HA cluster with embedded etcd.
# Designed for use with MetalLB (external LoadBalancer) and FluxCD (GitOps).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.k3s;
  dns = import ../../../lib/dns.nix;
in
{
  options.modules.k3s = {
    enable = lib.mkEnableOption "k3s Kubernetes";

    role = lib.mkOption {
      type = lib.types.enum [
        "server"
        "agent"
      ];
      default = "server";
      description = "k3s node role (server or agent)";
    };

    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Initialize a new HA cluster (only set true on first node)";
    };

    serverAddr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "URL of existing server to join (e.g., https://192.168.1.21:6443)";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the k3s cluster token";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags to pass to k3s";
    };
  };

  config = lib.mkIf cfg.enable {
    # Longhorn requirements
    services.openiscsi = {
      enable = true;
      name = config.networking.hostName;
    };

    # Longhorn expects iscsiadm in standard paths (it uses nsenter to run on host)
    systemd = {
      tmpfiles.rules = [
        "L+ /usr/local/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
        "d /usr/sbin 0755 root root -"
        "L+ /usr/sbin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
      ];

      # Workaround: k3s's embedded flannel can fail to regenerate /run/flannel/subnet.env
      # after a reboot (/run is tmpfs). Without this file, the flannel CNI plugin cannot
      # assign pod IPs and no pods can start. We persist a backup to disk and restore it
      # before k3s starts.
      services.k3s-flannel-restore = {
        description = "Restore flannel subnet.env from persistent backup";
        before = [ "k3s.service" ];
        requiredBy = [ "k3s.service" ];
        unitConfig.ConditionPathExists = "!/run/flannel/subnet.env";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /run/flannel
          BACKUP="/var/lib/rancher/k3s/flannel-subnet.env"
          if [ -f "$BACKUP" ]; then
            cp "$BACKUP" /run/flannel/subnet.env
            echo "Restored flannel subnet.env from $BACKUP"
          else
            echo "No flannel backup found at $BACKUP — first boot or backup missing"
          fi
        '';
      };

      services.k3s-flannel-backup = {
        description = "Backup flannel subnet.env to persistent storage";
        after = [ "k3s.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Wait for flannel to create subnet.env (up to 5 minutes)
          for i in $(seq 1 60); do
            if [ -f /run/flannel/subnet.env ]; then
              cp /run/flannel/subnet.env /var/lib/rancher/k3s/flannel-subnet.env
              echo "Backed up flannel subnet.env"
              exit 0
            fi
            sleep 5
          done
          echo "Warning: flannel subnet.env not found after 5 minutes"
        '';
      };
    };

    environment = {
      # Install kubectl for cluster management
      systemPackages = with pkgs; [
        kubectl
        kubernetes-helm
        fluxcd
      ];

      # Set KUBECONFIG for all users on server nodes
      sessionVariables = lib.mkIf (cfg.role == "server") {
        KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
      };

      # Configure containerd to trust internal Zot registry (HTTP)
      # Uses zot.lan (MetalLB LB at 192.168.1.56) so kubelet on the host
      # network can resolve and pull images from Zot.
      etc."rancher/k3s/registries.yaml".text = ''
        mirrors:
          "zot.lan:5000":
            endpoint:
              - "http://zot.lan:5000"
      '';
    };

    services.k3s = {
      enable = true;
      inherit (cfg) role clusterInit tokenFile;
      serverAddr = lib.mkIf (cfg.serverAddr != null) cfg.serverAddr;

      extraFlags = lib.concatStringsSep " " (
        [
          # Disable built-in components we're replacing
          "--disable=traefik" # Using external ingress or none
          "--disable=servicelb" # Using MetalLB instead
          # Flannel backend for pod networking
          "--flannel-backend=vxlan"
        ]
        ++ cfg.extraFlags
      );
    };

    # DNS servers for cluster nodes (AdGuard instances + fallback)
    networking.nameservers = dns.servers;

    # Firewall rules for k3s cluster
    networking.firewall = {
      allowedTCPPorts = [
        6443 # Kubernetes API server
        10250 # Kubelet metrics
        2379 # etcd client (HA clusters)
        2380 # etcd peer (HA clusters)
        7946 # MetalLB speaker memberlist
      ];

      allowedUDPPorts = [
        8472 # Flannel VXLAN
        7946 # MetalLB speaker memberlist
      ];
    };

    # Create kubeconfig symlink for easier access
    system.activationScripts.k3sKubeconfig = lib.mkIf (cfg.role == "server") ''
      mkdir -p /home/ammar/.kube
      if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        cp /etc/rancher/k3s/k3s.yaml /home/ammar/.kube/config
        chown ammar:users /home/ammar/.kube/config
        chmod 600 /home/ammar/.kube/config
      fi
    '';
  };
}
