# External monitoring and notification path for homelab outages.
# Gatus remains tailnet-only. ntfy is additionally published as authenticated
# HTTPS through Caddy; its native listener is never opened on the public NIC.
{ config, lib, ... }:

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
