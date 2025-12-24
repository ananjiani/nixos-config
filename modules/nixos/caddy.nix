# Caddy reverse proxy with automatic HTTPS
{ config, lib, ... }:

let
  cfg = config.modules.caddy;
in
{
  options.modules.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email for Let's Encrypt certificates";
    };

    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Map of domain -> upstream (e.g., localhost:8080)";
      example = {
        "app.example.com" = "localhost:3000";
        "api.example.com" = "localhost:8080";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      inherit (cfg) email;
      virtualHosts = lib.mapAttrs (_domain: upstream: {
        extraConfig = "reverse_proxy ${upstream}";
      }) cfg.virtualHosts;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
