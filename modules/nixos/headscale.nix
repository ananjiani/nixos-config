# Headscale - self-hosted Tailscale control server
{
  config,
  lib,
  pkgs,
  ...
}:

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

    aclPolicyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a HuJSON/JSON ACL policy file";
    };
  };

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;
      address = "127.0.0.1"; # Localhost only, reverse proxy handles external
      inherit (cfg) port;

      settings = {
        server_url = "https://${cfg.domain}";

        policy = lib.mkIf (cfg.aclPolicyFile != null) {
          mode = "file";
          path = pkgs.writeText "headscale-acl.json" (builtins.readFile cfg.aclPolicyFile);
        };

        dns = {
          base_domain = cfg.baseDomain;
          magic_dns = true;
          nameservers = {
            # Use same DNS as the host (AdGuard VIP → router)
            global = config.networking.nameservers;
            # Split DNS: route dimensiondoor.xyz queries to AdGuard so
            # split-DNS rewrites (ssh.git, git, auth, etc.) work for
            # Tailscale clients off-LAN (e.g. laptop at a coffee shop).
            # Without this, roaming clients hit public DNS which returns
            # NXDOMAIN for internal-only records like ssh.git.*.
            split = {
              # Use Tailscale IPs so this resolves off-LAN (equivalent HA to
              # the 192.168.1.53 keepalived VIP — all three run AdGuard and
              # bind 0.0.0.0 so they already listen on their Tailscale IPs).
              "dimensiondoor.xyz" = [
                "100.64.0.1" # boromir
                "100.64.0.2" # samwise
                "100.64.0.3" # theoden
              ];
            };
          };
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
