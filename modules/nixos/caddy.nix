# Caddy reverse proxy with automatic HTTPS
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.caddy;

  vhostType = lib.types.submodule {
    options = {
      upstream = lib.mkOption {
        type = lib.types.str;
        description = "Upstream target (e.g., localhost:8080)";
      };
      useCloudflareDns = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use Cloudflare DNS-01 for ACME instead of HTTP-01";
      };
    };
  };

  anyCloudflare = lib.any (v: v.useCloudflareDns) (lib.attrValues cfg.virtualHosts);
in
{
  options.modules.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email for Let's Encrypt certificates";
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf vhostType;
      default = { };
      description = "Map of domain -> vhost config (upstream + optional DNS-01)";
      example = lib.literalExpression ''
        {
          "app.example.com" = { upstream = "localhost:3000"; };
          "ts.example.com" = {
            upstream = "localhost:8080";
            useCloudflareDns = true;
          };
        }
      '';
    };

    cloudflareEnvFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "EnvironmentFile containing CF_API_TOKEN=... for DNS-01";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = anyCloudflare -> cfg.cloudflareEnvFile != null;
        message = "modules.caddy: cloudflareEnvFile is required when any vhost has useCloudflareDns = true";
      }
    ];

    services.caddy = {
      enable = true;
      inherit (cfg) email;

      package = lib.mkIf anyCloudflare (
        pkgs.caddy.withPlugins {
          plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
          hash = "sha256-hZKTEzevrabjgZCCcoRKlqUfdDIUr89KEFJ84kyFxeg=";
        }
      );

      virtualHosts = lib.mapAttrs (_domain: vhost: {
        extraConfig =
          lib.optionalString vhost.useCloudflareDns ''
            tls {
              dns cloudflare {env.CF_API_TOKEN}
            }
          ''
          + ''
            reverse_proxy ${vhost.upstream}
          '';
      }) cfg.virtualHosts;
    };

    systemd.services.caddy = lib.mkIf (cfg.cloudflareEnvFile != null) {
      serviceConfig.EnvironmentFile = cfg.cloudflareEnvFile;
      after = [ "vault-agent-default.service" ];
      wants = [ "vault-agent-default.service" ];
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
