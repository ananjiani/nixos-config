# Comin GitOps pull-deploy for always-on servers.
#
# Comin evaluates locally and asks the target Nix daemon to build. Attic and
# configured remote builders may satisfy that build. There is no automatic
# health rollback: suspend this service before a manual deploy-rs recovery so
# Comin does not immediately restore the current Git state.
{
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.modules.comin;
  lanHosts = import ../../lib/hosts.nix;
in
{
  imports = [ inputs.comin.nixosModules.comin ];

  options.modules.comin = {
    enable = lib.mkEnableOption "Comin GitOps pull deployment";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = lanHosts.${config.networking.hostName} or "";
      defaultText = lib.literalExpression ''lanHosts.''${config.networking.hostName} or ""'';
      description = ''
        Address for the Prometheus exporter (port 4243). Defaults to this
        host's LAN IP. Empty listens on all interfaces; pair that with a
        narrow firewall (do not expose the exporter on a public NIC).
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open TCP 4243 on the global NixOS firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.openFirewall -> cfg.listenAddress != "";
        message = "modules.comin.openFirewall requires a non-empty listenAddress; an empty address listens on all interfaces and the firewall would expose the exporter on every NIC.";
      }
    ];

    services.comin = {
      enable = true;
      debug = false;
      desktop.enable = false;
      # Keep prior boot entries / generations available for recovery.
      retention = {
        deployment_boot_entry_capacity = 3;
        deployment_successful_capacity = 3;
        deployment_any_capacity = 5;
      };
      exporter = {
        listen_address = cfg.listenAddress;
        port = 4243;
        openFirewall = false;
      };
      remotes = [
        {
          name = "origin";
          # Public remote; no repository token is needed.
          url = "https://codeberg.org/ananjiani/infra.git";
          branches = {
            main = {
              name = "main";
              operation = "switch";
            };
            testing = {
              # Default name is testing-''${hostname}; operation test.
              operation = "test";
            };
          };
        }
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 4243 ];

    # The exporter may bind an address that appears late (e.g. Erebor's
    # Tailscale IP). Wait for the network, and when binding still fails keep
    # retrying every 5s instead of hitting the systemd start limit and
    # leaving the agent dead until the next reboot.
    systemd.services.comin = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig.RestartSec = 5;
    };
  };
}
