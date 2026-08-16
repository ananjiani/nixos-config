# Zot OCI registry, hosted directly on the storage machine.
#
# Canonical data remains on /mnt/disk2/zot. Kubernetes keeps only the
# selectorless Service/EndpointSlice compatibility layer so existing cluster
# DNS and MetalLB clients continue to use their current addresses.
{ pkgs, ... }:
let
  zotConfig = (pkgs.formats.json { }).generate "zot-config.json" {
    storage = {
      rootDirectory = "/var/lib/zot";
      dedupe = false;
    };
    http = {
      address = "0.0.0.0";
      port = "5000";
      compat = [ "docker2s2" ];
    };
    log.level = "info";
    extensions = {
      sync = {
        enable = true;
        credentialsFile = "/etc/zot/credentials/credentials.json";
        registries = [
          {
            urls = [ "https://registry-1.docker.io" ];
            onDemand = true;
            tlsVerify = true;
            content = [ { prefix = "**"; } ];
          }
          {
            urls = [ "https://ghcr.io" ];
            onDemand = true;
            tlsVerify = true;
            content = [ { prefix = "catthehacker/ubuntu"; } ];
          }
          {
            urls = [ "https://code.forgejo.org" ];
            onDemand = true;
            tlsVerify = true;
            content = [ { prefix = "**"; } ];
          }
        ];
      };
      metrics = {
        enable = true;
        prometheus.path = "/metrics";
      };
    };
  };

  zotReady = pkgs.writeShellScript "zot-ready" ''
    for _ in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl -fsS --max-time 5 http://127.0.0.1:5000/v2/ >/dev/null; then
        exit 0
      fi
      sleep 10
    done
    echo "zot did not become ready within 10 minutes" >&2
    exit 1
  '';
in
{
  modules.vault-agent.secrets.zot-credentials = {
    path = "secret/nixos/zot";
    field = "credentials_json";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  virtualisation = {
    podman.enable = true;
    quadlet.containers.zot = {
      autoStart = true;
      containerConfig = {
        image = "ghcr.io/project-zot/zot-linux-amd64:v2.1.20";
        name = "zot";
        publishPorts = [ "5000:5000" ];
        exec = [
          "serve"
          "/etc/zot/config.json"
        ];
        volumes = [
          "${zotConfig}:/etc/zot/config.json:ro"
          "/run/secrets/zot-credentials:/etc/zot/credentials/credentials.json:ro"
          "/mnt/disk2/zot:/var/lib/zot"
        ];
        memory = "2g";
        logDriver = "journald";
      };
      unitConfig = {
        After = [
          "vault-agent-default.service"
          "mnt-disk2.mount"
        ];
        Requires = [ "vault-agent-default.service" ];
        BindsTo = [ "mnt-disk2.mount" ];
        PartOf = [ "mnt-disk2.mount" ];
        RequiresMountsFor = [ "/mnt/disk2" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = 10;
        TimeoutStartSec = 660;
        MemoryMax = "2G";
        CPUQuota = "200%";
        LogRateLimitIntervalSec = 30;
        LogRateLimitBurst = 1000;
        ExecStartPost = zotReady;
      };
    };
  };
}
