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
      default = "https://ts.dimensiondoor.xyz";
      description = "Headscale server URL";
    };

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = "/run/secrets/tailscale_authkey";
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
      default = false;
      description = "Accept DNS configuration from Tailscale/Headscale (MagicDNS)";
    };

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Accept subnet routes advertised by other nodes. Enable only on nodes that are NOT on the LAN to avoid circular routing.";
    };

    addHostsEntry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add a static /etc/hosts entry for the login server so it resolves without LAN DNS (safe to enable on LAN too — resolves to the same IP either way).";
    };

    useExitNode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Use specified node as exit node (hostname or IP). Set to null to disable.";
      example = "boromir";
    };

    exitNodeAllowLanAccess = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow direct access to local network when using an exit node";
    };

    operator = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Unprivileged user allowed to manage Tailscale (e.g., run tailscale down without sudo).";
      example = "ammar";
    };

    udpGroExcludeInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Physical interfaces to exclude from Tailscale UDP GRO forwarding optimization. Use this for NICs where enabling GRO causes packet loss (e.g. Realtek RTL8168).";
      example = [ "enp1s0" ];
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hosts = lib.mkIf cfg.addHostsEntry {
      "91.99.82.115" = [
        (lib.removePrefix "https://" (lib.removePrefix "http://" cfg.loginServer))
      ];
    };

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
      ++ lib.optionals (cfg.operator != null) [
        "--operator=${cfg.operator}"
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

    # Wrap tailscaled with mullvad-exclude to run outside VPN tunnel.
    # Must start after mullvad-daemon so the cgroup-based exclusion firewall
    # rules are in place — otherwise tailscaled's first login attempt is
    # caught by Mullvad's kill-switch and gets "connection refused" on all
    # outbound, leaving it stuck in NoState until manually restarted.
    #
    # The ExecStartPre poll waits for mullvad to report Connected (tunnel +
    # exclusion rules active) or Disconnected (no kill-switch, safe to proceed)
    # before launching tailscaled.  This prevents the boot-time race where
    # mullvad-daemon is "started" from systemd's perspective but its nftables
    # split-tunnel rules haven't been applied yet.
    systemd.services.tailscaled = lib.mkIf cfg.excludeFromMullvad {
      after = [ "mullvad-daemon.service" ];
      wants = [ "mullvad-daemon.service" ];
      serviceConfig = {
        ExecStartPre =
          let
            waitMullvad = pkgs.writeShellScript "wait-for-mullvad" ''
              for i in $(seq 1 60); do
                status=$(${config.services.mullvad-vpn.package}/bin/mullvad status 2>/dev/null)
                # Connected → tunnel + exclusion rules are active
                if echo "$status" | grep -q "Connected"; then
                  exit 0
                fi
                # Disconnected → no kill-switch, tailscaled can reach the internet directly
                if echo "$status" | grep -q "Disconnected"; then
                  exit 0
                fi
                sleep 1
              done
              # Timeout — proceed anyway, tailscaled will retry on its own
              exit 0
            '';
          in
          "${waitMullvad}";
        ExecStart = lib.mkForce [
          ""
          "${config.services.mullvad-vpn.package}/bin/mullvad-exclude ${config.services.tailscale.package}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=${toString config.services.tailscale.port}"
        ];
      };
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
      script =
        let
          excludeChecks = lib.concatMapStringsSep " && " (
            iface: ''[ "$iface" != "${iface}" ]''
          ) cfg.udpGroExcludeInterfaces;
          excludeCondition = lib.optionalString (cfg.udpGroExcludeInterfaces != [ ]) " && ${excludeChecks}";
        in
        ''
          for iface in /sys/class/net/*; do
            iface=$(basename "$iface")
            # Skip loopback, virtual interfaces, and excluded interfaces
            if [ "$iface" != "lo" ] && [ -d "/sys/class/net/$iface/device" ]${excludeCondition}; then
              ethtool -K "$iface" rx-udp-gro-forwarding on rx-gro-list off 2>/dev/null || true
            fi
          done
        '';
    };
  };
}
