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
    # Install kubectl for cluster management
    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      fluxcd
    ];

    # Set KUBECONFIG for all users on server nodes
    environment.sessionVariables = lib.mkIf (cfg.role == "server") {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
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

    # Firewall rules for k3s cluster
    networking.firewall = {
      allowedTCPPorts = [
        6443 # Kubernetes API server
        10250 # Kubelet metrics
        2379 # etcd client (HA clusters)
        2380 # etcd peer (HA clusters)
      ];

      allowedUDPPorts = [
        8472 # Flannel VXLAN
      ];

      # MetalLB L2 mode uses ARP, which works at layer 2
      # No additional firewall rules needed for MetalLB L2
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
