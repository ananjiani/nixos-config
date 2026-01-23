# Keepalived - VRRP for HA DNS failover
#
# Provides a floating VIP that automatically moves between servers
# based on health checks of the AdGuard DNS service.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.keepalived;
in
{
  options.modules.keepalived = {
    enable = lib.mkEnableOption "keepalived VRRP for HA DNS";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "ens18";
      description = "Network interface for VRRP";
    };

    virtualIp = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.53/24";
      description = "Floating virtual IP address";
    };

    priority = lib.mkOption {
      type = lib.types.int;
      description = "VRRP priority (higher wins election)";
    };

    routerId = lib.mkOption {
      type = lib.types.int;
      default = 53;
      description = "VRRP virtual router ID (1-255)";
    };

    unicastPeers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of peer IP addresses for unicast VRRP (required for Proxmox VMs)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create keepalived_script user for running health check scripts
    users.users.keepalived_script = {
      isSystemUser = true;
      group = "keepalived_script";
    };
    users.groups.keepalived_script = { };

    services.keepalived = {
      enable = true;
      openFirewall = true;

      vrrpScripts.check_adguard = {
        script = "${pkgs.dig}/bin/dig @127.0.0.1 +short +time=2 router.lan A";
        interval = 2;
        fall = 3;
        rise = 2;
        timeout = 3;
        weight = 0;
        user = "keepalived_script";
        group = "keepalived_script";
      };

      vrrpInstances.adguard_vip = {
        inherit (cfg) interface priority unicastPeers;
        state = "BACKUP";
        virtualRouterId = cfg.routerId;
        noPreempt = false;
        virtualIps = [ { addr = cfg.virtualIp; } ];
        trackScripts = [ "check_adguard" ];
      };
    };
  };
}
