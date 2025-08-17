# VPN configuration for torrent traffic (Mullvad + qBittorrent)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.homeserver-vpn-torrents;
  # Network namespace for VPN isolation
  vpnNamespace = "vpn";
  vpnInterface = "wg-mullvad";
in
{
  options.services.homeserver-vpn-torrents = {
    enable = lib.mkEnableOption "VPN-isolated torrent client";

    qbittorrentPort = lib.mkOption {
      type = lib.types.port;
      default = 8118;
      description = "Port for qBittorrent web UI";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/storage2/arr-data/torrents";
      description = "Directory for torrent downloads";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/storage2/arr-data/config/qbittorrent";
    };

    # Mullvad configuration - to be passed from main config
    mullvadPrivateKey = lib.mkOption {
      type = lib.types.str;
      description = "Mullvad WireGuard private key";
    };

    mullvadAddress = lib.mkOption {
      type = lib.types.str;
      description = "Mullvad WireGuard IP address";
    };

    mullvadPublicKey = lib.mkOption {
      type = lib.types.str;
      description = "Mullvad server public key";
    };

    mullvadEndpoint = lib.mkOption {
      type = lib.types.str;
      description = "Mullvad server endpoint";
    };
  };

  config = lib.mkIf cfg.enable {
    # WireGuard configuration for Mullvad
    networking.wireguard.interfaces.${vpnInterface} = {
      # Run in the VPN namespace
      interfaceNamespace = vpnNamespace;

      # Private key - for now just use the value directly
      # TODO: Use SOPS in production
      privateKey = cfg.mullvadPrivateKey;

      # Mullvad configuration
      ips = [ cfg.mullvadAddress ];

      peers = [
        {
          publicKey = cfg.mullvadPublicKey;
          allowedIPs = [
            "0.0.0.0/0"
            "::0/0"
          ];
          endpoint = cfg.mullvadEndpoint;
        }
      ];

      # Kill switch - ensure all traffic goes through VPN
      postSetup = ''
        ${pkgs.iproute2}/bin/ip -n ${vpnNamespace} route add default dev ${vpnInterface}
        ${pkgs.iproute2}/bin/ip -n ${vpnNamespace} -6 route add default dev ${vpnInterface}
      '';
    };

    # System services for VPN namespace and qBittorrent
    systemd.services = {
      # Create network namespace for VPN isolation
      vpn-namespace = {
        description = "Create VPN network namespace";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "create-vpn-namespace" ''
            ${pkgs.iproute2}/bin/ip netns add ${vpnNamespace} || true
            ${pkgs.iproute2}/bin/ip -n ${vpnNamespace} link set lo up
          '';
          ExecStop = pkgs.writeShellScript "destroy-vpn-namespace" ''
            ${pkgs.iproute2}/bin/ip netns delete ${vpnNamespace} || true
          '';
        };
      };

      # qBittorrent service running in VPN namespace
      qbittorrent = {
        description = "qBittorrent (in VPN namespace)";
        after = [
          "network.target"
          "vpn-namespace.service"
          "wireguard-${vpnInterface}.service"
        ];
        requires = [
          "vpn-namespace.service"
          "wireguard-${vpnInterface}.service"
        ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          User = "media";
          Group = "media";
          UMask = "0002";

          # Run in VPN namespace
          NetworkNamespacePath = "/var/run/netns/${vpnNamespace}";

          # Security hardening
          PrivateTmp = true;
          NoNewPrivileges = true;

          ExecStart = ''
            ${pkgs.qbittorrent-nox}/bin/qbittorrent-nox \
              --webui-port=${toString cfg.qbittorrentPort} \
              --profile=${cfg.configDir}
          '';

          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      # Proxy service to access qBittorrent from host network
      qbittorrent-proxy = {
        description = "Proxy for qBittorrent web UI";
        after = [ "qbittorrent.service" ];
        requires = [ "qbittorrent.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          DynamicUser = true;

          ExecStart = ''
            ${pkgs.socat}/bin/socat \
              TCP-LISTEN:${toString cfg.qbittorrentPort},fork,reuseaddr \
              EXEC:'${pkgs.iproute2}/bin/ip netns exec ${vpnNamespace} ${pkgs.socat}/bin/socat STDIO TCP:localhost:${toString cfg.qbittorrentPort}'
          '';

          Restart = "always";
          RestartSec = "5s";
        };
      };

      # Create directories
      tmpfiles.rules = [
        "d '${cfg.dataDir}' 0755 media media -"
        "d '${cfg.configDir}' 0755 media media -"
      ];
    };

    # Ensure media user exists (from media.nix)
    users.users.media = {
      isSystemUser = true;
      group = "media";
      uid = 1000;
    };
    users.groups.media = {
      gid = 1000;
    };

    # Firewall - only allow qBittorrent UI access
    networking.firewall.allowedTCPPorts = [ cfg.qbittorrentPort ];

  };
}
