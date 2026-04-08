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
  lanHosts = import ../../../lib/hosts.nix;
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
      default = if cfg.clusterInit then null else "https://${lanHosts.boromir}:6443";
      defaultText = lib.literalExpression ''if cfg.clusterInit then null else "https://''${lanHosts.boromir}:6443"'';
      description = "URL of existing server to join. Null when clusterInit is true, otherwise defaults to boromir.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/k3s_token";
      description = "Path to file containing the k3s cluster token";
    };

    nodeIp = lib.mkOption {
      type = lib.types.str;
      default = lanHosts.${config.networking.hostName};
      defaultText = lib.literalExpression "lanHosts.\${config.networking.hostName}";
      description = "Primary IPv4 address of this node (used for --node-ip). Defaults to lookup from lib/hosts.nix.";
    };

    flannelIface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "ens18";
      description = ''
        Network interface for flannel inter-host communication.
        Defaults to "ens18" (Proxmox virtio NIC). Override for bare metal.
        Prevents flannel from picking up keepalived VIPs as its public-ip,
        which corrupts host-gw routes across the cluster.
        Set to null to let flannel auto-detect (safe if no VIPs on the interface).
      '';
    };

    podCidr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.42.1.0/24";
      description = ''
        Pod CIDR assigned to this node by the k3s API server.
        Used as a fallback to generate /run/flannel/subnet.env when
        no persistent backup exists (e.g. after power loss or first
        deploy with host-gw backend). Check with:
          kubectl get node <name> -o jsonpath='{.spec.podCIDR}'
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags to pass to k3s";
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      # NFS client support — ensures mount.nfs is available so kubelet can
      # mount NFS-backed PersistentVolumes on any k3s node.
      supportedFilesystems = [ "nfs" ];

      # IPVS kernel modules for kube-proxy IPVS mode
      kernelModules = [
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
      ];
      kernel.sysctl = {
        # IP forwarding — required for flannel to route cross-node pod traffic.
        # Without this, packets arriving on the host destined for the pod CIDR
        # are dropped instead of being forwarded to the cni0 bridge.
        # (Server nodes often get this from the Tailscale module, but agent
        # nodes like rivendell with Tailscale disabled need it explicitly.)
        "net.ipv4.ip_forward" = lib.mkDefault 1;
        "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;

        # IPVS ARP suppression: kube-proxy IPVS mode binds all LoadBalancer and
        # ClusterIP addresses to the kube-ipvs0 dummy interface on every node.
        # Without these sysctls, every node responds to ARP for those IPs,
        # causing traffic to land on the wrong node (whichever wins the ARP race)
        # instead of the MetalLB L2 speaker that should own the IP.
        #   arp_ignore=1:  only respond if the target IP is on the incoming interface
        #   arp_announce=2: use the best local address matching the destination subnet
        "net.ipv4.conf.all.arp_ignore" = 1;
        "net.ipv4.conf.all.arp_announce" = 2;
      };
    };

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

        # Scale CoreDNS to 2 replicas spread across nodes for DNS resilience.
        # k3s deploys CoreDNS as an Addon (not HelmChart), so HelmChartConfig
        # doesn't work. This runs after k3s starts to patch the deployment.
        k3s-coredns-ha = lib.mkIf (cfg.role == "server") {
          description = "Scale CoreDNS to 2 replicas across nodes";
          after = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.kubectl ];
          script = ''
            export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

            # Wait for CoreDNS deployment to exist (up to 5 min)
            for i in $(seq 1 60); do
              if kubectl get deploy coredns -n kube-system &>/dev/null; then
                break
              fi
              sleep 5
            done

            if ! kubectl get deploy coredns -n kube-system &>/dev/null; then
              echo "CoreDNS deployment not found, skipping"
              exit 0
            fi

            CURRENT=$(kubectl get deploy coredns -n kube-system -o jsonpath='{.spec.replicas}')
            if [ "$CURRENT" != "2" ]; then
              echo "Scaling CoreDNS: $CURRENT → 2 replicas"
              kubectl scale deploy coredns -n kube-system --replicas=2
            else
              echo "CoreDNS already at 2 replicas"
            fi
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
          script =
            let
              # Derive the gateway IP (.1) from the podCidr (e.g. 10.42.1.0/24 → 10.42.1.1/24)
              fallbackScript = lib.optionalString (cfg.podCidr != null) ''
                elif [ ! -f /run/flannel/subnet.env ]; then
                  # Generate from declarative podCidr — covers first boot, power loss,
                  # or any scenario where the backup is missing.
                  SUBNET=$(echo "${cfg.podCidr}" | sed 's|\.[0-9]*/|.1/|')
                  printf '%s\n' \
                    "FLANNEL_NETWORK=10.42.0.0/16" \
                    "FLANNEL_SUBNET=$SUBNET" \
                    "FLANNEL_MTU=1500" \
                    "FLANNEL_IPMASQ=true" \
                    > /run/flannel/subnet.env
                  echo "Generated flannel subnet.env from declared podCidr ${cfg.podCidr}"
              '';
            in
            ''
              mkdir -p /run/flannel
              BACKUP="/var/lib/rancher/k3s/flannel-subnet.env"
              if [ -f "$BACKUP" ]; then
                cp "$BACKUP" /run/flannel/subnet.env
                echo "Restored flannel subnet.env from $BACKUP"
              ${fallbackScript}
              else
                echo "No flannel backup found at $BACKUP — first boot or backup missing"
              fi
            '';
        };

        # Workaround: the cni0 bridge retains the MTU from when it was first created.
        # If flannel's backend changed (e.g. VXLAN 1450 → host-gw 1500), the bridge
        # keeps the old MTU until manually corrected. This reads the correct MTU from
        # flannel's subnet.env and applies it to cni0 and all attached veth interfaces.
        k3s-flannel-mtu = {
          description = "Ensure cni0 bridge MTU matches flannel config";
          after = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.iproute2 ];
          script = ''
            # Wait for cni0 to exist (up to 2 minutes)
            for i in $(seq 1 24); do
              if ip link show cni0 &>/dev/null; then
                break
              fi
              sleep 5
            done

            if ! ip link show cni0 &>/dev/null; then
              echo "cni0 not found, skipping MTU fix"
              exit 0
            fi

            # Read MTU from flannel config
            if [ -f /run/flannel/subnet.env ]; then
              . /run/flannel/subnet.env
              DESIRED_MTU=''${FLANNEL_MTU:-1500}
            else
              DESIRED_MTU=1500
            fi

            CURRENT_MTU=$(cat /sys/class/net/cni0/mtu)
            if [ "$CURRENT_MTU" != "$DESIRED_MTU" ]; then
              echo "Fixing cni0 MTU: $CURRENT_MTU → $DESIRED_MTU"
              ip link set cni0 mtu "$DESIRED_MTU"
              # Update all veth interfaces attached to cni0
              for veth in $(ip link show master cni0 | grep -oP '^\d+: \K[^@]+'); do
                ip link set "$veth" mtu "$DESIRED_MTU"
              done
            else
              echo "cni0 MTU already correct: $CURRENT_MTU"
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
        ipvsadm # IPVS management for kube-proxy IPVS mode
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
          # Use node external IPs for flannel inter-node routing.
          # With --node-external-ip set to the real node IP, this forces flannel
          # to use that IP instead of auto-detecting (which picks up keepalived VIPs).
          "--flannel-external-ip"
          # TODO: Enable dual-stack IPv6 for pods (fd42::/48, fd43::/48).
          # Blocked by k3s flannel bug: single-stack → dual-stack migration causes
          # nil pointer panic in WriteSubnetFile (github.com/k3s-io/k3s#10726).
          # Requires deleting all node objects and restarting simultaneously.
          # For now, pods remain IPv4-only; host IPv6 egress works via hostNetwork.
        ]
        # Flags for all nodes (server + agent)
        ++ [
          # IPVS proxy mode: O(1) hash-table lookups instead of O(n) iptables
          # chain traversal. With 61 services generating ~1300 iptables rules,
          # this significantly reduces per-packet CPU overhead.
          "--kube-proxy-arg=proxy-mode=ipvs"
          "--node-ip=${cfg.nodeIp}"
          # Also set --node-external-ip to trigger the k3s CCM to annotate the
          # node with flannel.alpha.coreos.com/public-ip-overwrite. Without this,
          # flannel auto-detects the IP from the interface and may pick up a
          # keepalived VIP instead of the real node IP.
          "--node-external-ip=${cfg.nodeIp}"
        ]
        # Pin flannel to a specific interface — prevents keepalived VIPs
        # (bound to the same interface) from being used as flannel public-ip,
        # which corrupts host-gw routes across the cluster.
        ++ lib.optional (cfg.flannelIface != null) "--flannel-iface=${cfg.flannelIface}"
        ++ cfg.extraFlags
      );
    };

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

      # IPVS mode: pod→ClusterIP traffic arrives on INPUT chain via cni0 bridge.
      # Without this, NixOS firewall drops it before IPVS can intercept.
      # (In iptables kube-proxy mode, traffic was DNAT'd in PREROUTING so this
      # wasn't needed.)
      #
      # MetalLB LoadBalancer IPs (192.168.1.52-62) are bound to kube-ipvs0,
      # so external LAN traffic to these IPs also enters the INPUT chain.
      # Without this rule, the firewall drops it before IPVS can forward
      # to the backend pods (e.g. Traefik on ports 80/443).
      extraCommands = ''
        iptables -I nixos-fw 1 -i cni0 -s 10.42.0.0/16 -d 10.43.0.0/16 -j nixos-fw-accept
        iptables -I nixos-fw 2 -d 192.168.1.52/28 -j nixos-fw-accept
      '';
      extraStopCommands = ''
        iptables -D nixos-fw -i cni0 -s 10.42.0.0/16 -d 10.43.0.0/16 -j nixos-fw-accept 2>/dev/null || true
        iptables -D nixos-fw -d 192.168.1.52/28 -j nixos-fw-accept 2>/dev/null || true
      '';
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

    # Auto-register k3s token with vault-agent when both are enabled
    modules.vault-agent.secrets.k3s_token = lib.mkIf config.modules.vault-agent.enable {
      path = "secret/nixos/k3s";
      field = "token";
    };
  };
}
