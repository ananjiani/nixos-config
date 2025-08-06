# Nginx reverse proxy configuration for homeserver services
{ config, lib, ... }:

let
  cfg = config.services.homeserver-proxy;
in
{
  options.services.homeserver-proxy = {
    enable = lib.mkEnableOption "homeserver reverse proxy";

    baseDomain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain for all services";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Email for Let's Encrypt certificates";
    };
  };

  config = lib.mkIf cfg.enable {
    # Nginx configuration
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
    };

    # ACME (Let's Encrypt) configuration
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    # Open firewall for HTTP/HTTPS
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
