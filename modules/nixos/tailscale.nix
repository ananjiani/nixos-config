# Tailscale client for Headscale mesh VPN
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.tailscale;
in
{
  options.modules.tailscale = {
    enable = lib.mkEnableOption "Tailscale client";

    loginServer = lib.mkOption {
      type = lib.types.str;
      description = "Headscale server URL (e.g., https://ts.example.com)";
    };

    exitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise this node as an exit node";
    };

    subnetRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Subnet routes to advertise (e.g., [\"192.168.1.0/24\"])";
      example = [
        "192.168.1.0/24"
        "10.0.0.0/8"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = if cfg.exitNode || cfg.subnetRoutes != [ ] then "both" else "client";
      extraUpFlags = [
        "--login-server=${cfg.loginServer}"
      ]
      ++ lib.optionals cfg.exitNode [ "--advertise-exit-node" ]
      ++ lib.optionals (cfg.subnetRoutes != [ ]) [
        "--advertise-routes=${lib.concatStringsSep "," cfg.subnetRoutes}"
      ];
    };

    # Exit node and subnet routing require IP forwarding
    boot.kernel.sysctl = lib.mkIf (cfg.exitNode || cfg.subnetRoutes != [ ]) {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # Open Tailscale port
    networking.firewall = {
      allowedUDPPorts = [ 41641 ];
      # Trust Tailscale interface
      trustedInterfaces = [ "tailscale0" ];
    };

    # Optimize UDP GRO forwarding for better throughput
    # See: https://tailscale.com/s/ethtool-config-udp-gro
    systemd.services.tailscale-udp-gro = {
      description = "Configure UDP GRO forwarding for Tailscale";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.ethtool ];
      script = ''
        for iface in /sys/class/net/*; do
          iface=$(basename "$iface")
          # Skip loopback and virtual interfaces
          if [ "$iface" != "lo" ] && [ -d "/sys/class/net/$iface/device" ]; then
            ethtool -K "$iface" rx-udp-gro-forwarding on rx-gro-list off 2>/dev/null || true
          fi
        done
      '';
    };
  };
}
