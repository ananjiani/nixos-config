# Headscale - self-hosted Tailscale control server
{ config, lib, ... }:

let
  cfg = config.modules.headscale;
in
{
  options.modules.headscale = {
    enable = lib.mkEnableOption "Headscale server";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public domain for Headscale (e.g., ts.example.com)";
    };

    baseDomain = lib.mkOption {
      type = lib.types.str;
      default = "tail.net";
      description = "Base domain for MagicDNS (devices get <name>.<baseDomain>)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for Headscale to listen on (behind reverse proxy)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;
      address = "127.0.0.1"; # Localhost only, reverse proxy handles external
      inherit (cfg) port;

      settings = {
        server_url = "https://${cfg.domain}";

        dns = {
          base_domain = cfg.baseDomain;
          magic_dns = true;
          # Use AdGuard Home on boromir for .lan resolution
          # AdGuard forwards external queries to upstream DNS
          nameservers.global = [
            "192.168.1.21"
          ];
        };

        prefixes = {
          v4 = "100.64.0.0/10"; # CGNAT range used by Tailscale
          v6 = "fd7a:115c:a1e0::/48";
        };

        # Disable open registration - use CLI to create users/keys
        disable_check_updates = true;

        # Log configuration
        log = {
          level = "info";
        };
      };
    };

    # Headscale CLI available system-wide
    environment.systemPackages = [ config.services.headscale.package ];
  };
}
