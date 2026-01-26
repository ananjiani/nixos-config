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

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing auth key for automatic registration";
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

    excludeFromMullvad = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run tailscaled outside Mullvad VPN tunnel using mullvad-exclude";
    };

    acceptDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Accept DNS configuration from Tailscale/Headscale (MagicDNS)";
    };

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Accept subnet routes advertised by other nodes. Disable on nodes that are already on the LAN and advertise subnet routes to avoid circular routing.";
    };

    useExitNode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "boromir";
      description = "Use specified node as exit node (hostname or IP). Set to null to disable.";
      example = "boromir";
    };

    exitNodeAllowLanAccess = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow direct access to local network when using an exit node";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = if cfg.exitNode || cfg.subnetRoutes != [ ] then "both" else "client";
      inherit (cfg) authKeyFile;
      extraUpFlags = [
        "--login-server=${cfg.loginServer}"
        "--reset" # Override any existing settings from previous runs
      ]
      ++ lib.optionals cfg.exitNode [ "--advertise-exit-node" ]
      ++ lib.optionals (cfg.subnetRoutes != [ ]) [
        "--advertise-routes=${lib.concatStringsSep "," cfg.subnetRoutes}"
      ];
      extraSetFlags = [
        "--accept-dns=${lib.boolToString cfg.acceptDns}"
        "--accept-routes=${lib.boolToString cfg.acceptRoutes}"
      ]
      ++ lib.optionals (cfg.useExitNode != null) [
        "--exit-node=${cfg.useExitNode}"
        "--exit-node-allow-lan-access=${lib.boolToString cfg.exitNodeAllowLanAccess}"
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

    # Wrap tailscaled with mullvad-exclude to run outside VPN tunnel
    systemd.services.tailscaled = lib.mkIf cfg.excludeFromMullvad {
      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${pkgs.mullvad}/bin/mullvad-exclude ${config.services.tailscale.package}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=${toString config.services.tailscale.port}"
      ];
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
