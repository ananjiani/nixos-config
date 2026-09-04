# Comin GitOps pull-deploy for always-on servers.
#
# Comin evaluates locally and asks the target Nix daemon to build. Attic and
# configured remote builders may satisfy that build. There is no automatic
# health rollback: suspend this service before a manual deploy-rs recovery so
# Comin does not immediately restore the current Git state.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.modules.comin;
  lanHosts = import ../../lib/hosts.nix;
  rebootCfg = cfg.autoReboot;

  metricsAddr = if cfg.listenAddress == "" then "127.0.0.1" else cfg.listenAddress;

  autoRebootScript = pkgs.writeShellScript "comin-auto-reboot" ''
    set -eu
    log() { echo "comin-auto-reboot: $*"; }

    metrics_url="http://${metricsAddr}:4243/metrics"
    log "querying $metrics_url"

    metrics=$(${pkgs.curl}/bin/curl -fsS --max-time 10 "$metrics_url") || {
      log "metrics fetch failed; skipping reboot"
      exit 0
    }

    need=$(printf '%s\n' "$metrics" | ${pkgs.gawk}/bin/awk '
      /^comin_need_to_reboot([ {]|$)/ { print $NF; exit }
    ')
    if [ -z "$need" ]; then
      log "comin_need_to_reboot missing; skipping reboot"
      exit 0
    fi
    case "$need" in
      1|1.0) log "comin_need_to_reboot=$need" ;;
      *)
        log "comin_need_to_reboot=$need; skipping reboot"
        exit 0
        ;;
    esac

    uptime_sec=$(${pkgs.gawk}/bin/awk '{ print int($1) }' /proc/uptime)
    if [ "$uptime_sec" -le ${toString rebootCfg.minUptimeSec} ]; then
      log "uptime ''${uptime_sec}s <= minUptimeSec ${toString rebootCfg.minUptimeSec}; skipping reboot"
      exit 0
    fi
    log "uptime ''${uptime_sec}s ok"

    sessions_out=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend || true)
    if [ -n "$sessions_out" ]; then
      log "active session(s) present; skipping reboot"
      printf '%s\n' "$sessions_out"
      exit 0
    fi
    log "no active sessions"

    ${lib.optionalString (rebootCfg.preRebootCheck != null) ''
      log "running preRebootCheck"
      if ! (
      ${rebootCfg.preRebootCheck}
      ); then
        log "preRebootCheck failed; skipping reboot"
        exit 0
      fi
      log "preRebootCheck ok"
    ''}

    log "rebooting"
    ${pkgs.systemd}/bin/systemctl reboot
  '';
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

    autoReboot = {
      enable = lib.mkEnableOption "unattended reboot when Comin reports need_to_reboot";

      calendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 04:00:00";
        description = "systemd OnCalendar for the auto-reboot timer.";
      };

      minUptimeSec = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 3600;
        description = "Skip reboot when host uptime is at or below this many seconds.";
      };

      preRebootCheck = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = ''
          Optional extra shell check that must exit 0 to allow reboot.
          Non-zero skips the reboot (main unit still exits 0).
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
    })

    (lib.mkIf (cfg.enable && rebootCfg.enable) {
      systemd.services.comin-auto-reboot = {
        description = "Reboot when Comin reports a needed reboot";
        path = [
          pkgs.curl
          pkgs.gawk
          pkgs.coreutils
          pkgs.systemd
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = autoRebootScript;
        };
      };

      systemd.timers.comin-auto-reboot = {
        description = "Daily Comin need-to-reboot check";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = rebootCfg.calendar;
          Persistent = false;
          Unit = "comin-auto-reboot.service";
        };
      };
    })
  ];
}
