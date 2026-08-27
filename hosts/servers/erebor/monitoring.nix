# External monitoring and notification path for homelab outages.
# Gatus remains tailnet-only. ntfy is additionally published as authenticated
# HTTPS through Caddy; its native listener is never opened on the public NIC.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  ntfyAlert = {
    type = "ntfy";
    description = "External service health check failed";
  };

  mkEndpoint =
    {
      name,
      url,
      conditions ? [
        "[STATUS] == 200"
        "[RESPONSE_TIME] < 5000"
        "[CERTIFICATE_EXPIRATION] > 168h"
      ],
    }:
    {
      inherit name url conditions;
      group = "external";
      interval = "1m";
      alerts = [ ntfyAlert ];
    };

  monitoringStackHeartbeat = pkgs.writeShellApplication {
    name = "monitoring-stack-heartbeat";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.systemd
      pkgs.tailscale
    ];
    text = ''
      for unit in gatus.service ntfy-sh.service tailscaled.service; do
        systemctl is-active --quiet "$unit"
      done

      curl --fail --silent --show-error --max-time 5 \
        http://127.0.0.1:2586/v1/health \
        | jq --exit-status '.healthy == true' >/dev/null

      curl --fail --silent --show-error --max-time 5 \
        http://127.0.0.1:8081/api/v1/endpoints/statuses \
        | jq --exit-status '
            type == "array"
            and length > 0
            and all(.[].results;
              length > 0
              and (
                now
                - (.[-1].timestamp
                  | sub("\\.[0-9]+Z$"; "Z")
                  | fromdateiso8601)
              ) < 180
            )
          ' >/dev/null

      tailscale status --json \
        | jq --exit-status '.BackendState == "Running"' >/dev/null

      curl --config /run/secrets/healthchecks-stack-curl-config --output /dev/null
    '';
  };

  heartbeatServiceHardening = {
    Type = "oneshot";
    User = "root";
    TimeoutStartSec = "30s";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    CapabilityBoundingSet = "";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    SystemCallArchitectures = "native";
  };
in
{
  services = {
    ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.dimensiondoor.xyz";
        listen-http = "0.0.0.0:2586";
        behind-proxy = true;
        auth-default-access = "deny-all";
        cache-duration = "168h";
        attachment-total-size-limit = "0";
        visitor-request-limit-burst = 60;
        visitor-request-limit-replenish = "5s";
      };
    };

    gatus = {
      enable = true;
      settings = {
        web.port = 8081;

        storage = {
          type = "sqlite";
          path = "/var/lib/gatus/data.db";
        };

        alerting.ntfy = {
          url = "http://127.0.0.1:2586";
          topic = "monitoring";
          token = "\${GATUS_NTFY_TOKEN}";
          priority = 4;
          default-alert = {
            failure-threshold = 3;
            success-threshold = 2;
            send-on-resolved = true;
          };
        };

        endpoints = [
          (mkEndpoint {
            name = "Headscale control plane";
            url = "https://ts.dimensiondoor.xyz/health";
          })
          (mkEndpoint {
            name = "Buildbot CI";
            url = "https://ci.dimensiondoor.xyz/";
          })
          (mkEndpoint {
            name = "Attic binary cache";
            url = "https://attic.dimensiondoor.xyz/middle-earth/nix-cache-info";
          })
          (mkEndpoint {
            name = "Voicemail receiver";
            url = "https://voicemail.dimensiondoor.xyz/health";
          })
        ];
      };
    };
  };

  # Bind the services on all addresses so they survive Tailscale address
  # changes. The shared networking module trusts tailscale0, so these entries
  # document the intended listeners; the global firewall remains the boundary
  # that prevents either port from being reachable on Erebor's public NIC.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    2586
    8081
    4243 # Comin exporter; not on the public NIC
  ];

  systemd.services = {
    healthchecks-host-heartbeat = {
      description = "Report Erebor host liveness to Healthchecks.io";
      after = [
        "network-online.target"
        "vault-agent-default.service"
      ];
      wants = [
        "network-online.target"
        "vault-agent-default.service"
      ];
      unitConfig.ConditionPathExists = "/run/secrets/healthchecks-host-curl-config";
      serviceConfig = heartbeatServiceHardening // {
        ExecStart = "${pkgs.curl}/bin/curl --config /run/secrets/healthchecks-host-curl-config --output /dev/null";
      };
    };

    healthchecks-stack-heartbeat = {
      description = "Report Erebor monitoring-stack liveness to Healthchecks.io";
      after = [
        "gatus.service"
        "network-online.target"
        "ntfy-sh.service"
        "tailscaled.service"
        "vault-agent-default.service"
      ];
      wants = [
        "network-online.target"
        "vault-agent-default.service"
      ];
      unitConfig.ConditionPathExists = "/run/secrets/healthchecks-stack-curl-config";
      serviceConfig = heartbeatServiceHardening // {
        ExecStart = "${monitoringStackHeartbeat}/bin/monitoring-stack-heartbeat";
      };
    };

    ntfy-sh = {
      after = [ "vault-agent-default.service" ];
      wants = [ "vault-agent-default.service" ];
      serviceConfig = {
        EnvironmentFile = "/run/secrets/ntfy-auth-env";
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "128M";
        CPUQuota = "25%";
      };
    };

    gatus = {
      after = [
        "ntfy-sh.service"
        "vault-agent-default.service"
      ];
      wants = [
        "ntfy-sh.service"
        "vault-agent-default.service"
      ];
      serviceConfig = {
        EnvironmentFile = "/run/secrets/gatus-ntfy-env";
        MemoryMax = "256M";
        CPUQuota = "50%";
      };
    };
  };

  systemd.timers = {
    healthchecks-host-heartbeat = {
      description = "Run the Erebor host heartbeat every five minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
        RandomizedDelaySec = "15s";
        AccuracySec = "10s";
      };
    };

    healthchecks-stack-heartbeat = {
      description = "Run the monitoring-stack heartbeat every five minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3m";
        OnUnitActiveSec = "5m";
        RandomizedDelaySec = "15s";
        AccuracySec = "10s";
      };
    };
  };

  assertions = [
    {
      assertion = lib.all (port: !(lib.elem port config.networking.firewall.allowedTCPPorts)) [
        2586
        8081
      ];
      message = "External monitoring ports must not be opened on Erebor's public interfaces";
    }
  ];
}
