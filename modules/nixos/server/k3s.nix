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

      services = {
        # Gracefully drain this node before k3s stops during shutdown.
        # Tells the cluster to reschedule pods elsewhere before we disappear.
        # After=k3s.service means: start after k3s, stop BEFORE k3s (reverse order).
        k3s-graceful-drain = lib.mkIf (cfg.role == "server") {
          description = "Drain k3s node before shutdown";
          after = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
            ExecStop =
              let
                drainScript = pkgs.writeShellScript "k3s-drain" ''
                  NODE=$(${pkgs.hostname}/bin/hostname)
                  echo "Cordoning $NODE..."
                  ${pkgs.kubectl}/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml \
                    cordon "$NODE" || true
                  echo "Draining $NODE..."
                  ${pkgs.kubectl}/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml \
                    drain "$NODE" \
                    --ignore-daemonsets \
                    --delete-emptydir-data \
                    --disable-eviction \
                    --timeout=60s || true
                  echo "Drain complete for $NODE"
                '';
              in
              "${drainScript}";
          };
        };

        # Uncordon this node after k3s starts, reversing the cordon from the drain hook.
        # Waits for the node to be Ready before uncordoning so pods can schedule immediately.
        k3s-auto-uncordon = lib.mkIf (cfg.role == "server") {
          description = "Uncordon k3s node after startup";
          after = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            NODE=$(${pkgs.hostname}/bin/hostname)
            export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

            # Wait for the API server and this node to be Ready (up to 5 min)
            for i in $(seq 1 60); do
              STATUS=$(${pkgs.kubectl}/bin/kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null) || true
              if [ "$STATUS" = "True" ]; then
                ${pkgs.kubectl}/bin/kubectl uncordon "$NODE"
                echo "Uncordoned $NODE"
                exit 0
              fi
              sleep 5
            done
            echo "Warning: $NODE did not become Ready within 5 minutes, skipping uncordon"
          '';
        };

        # Workaround: k3s's embedded flannel can fail to regenerate /run/flannel/subnet.env
        # after a reboot (/run is tmpfs). Without this file, the flannel CNI plugin cannot
        # assign pod IPs and no pods can start. We persist a backup to disk and restore it
        # before k3s starts.
        k3s-flannel-restore = {
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

        k3s-flannel-backup = {
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
        lib.optionals (cfg.role == "server") [
          # Disable built-in components we're replacing (server-only flags)
          "--disable=traefik" # Using external ingress or none
          "--disable=servicelb" # Using MetalLB instead
          # Flannel backend: host-gw adds static routes instead of VXLAN encapsulation.
          # Requires all nodes on the same L2 subnet (ours are all 192.168.1.x).
          # Gives pods full 1500-byte MTU — avoids the VXLAN overhead that caused
          # repeated HTTP/2 + TLS framing failures (see postmortem 2026-02-01-0445).
          "--flannel-backend=host-gw"
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
