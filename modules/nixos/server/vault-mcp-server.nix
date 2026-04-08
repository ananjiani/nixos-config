# Vault MCP Server — Model Context Protocol interface for OpenBao
#
# Runs the HashiCorp Vault MCP server in streamable-http mode, allowing
# Claude Code and other MCP clients to manage secrets via natural language.
# The token's policy controls access — mcp-metadata allows structure browsing
# and writes, but not plaintext reads.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.vault-mcp-server;

  vault-mcp-server = pkgs.stdenv.mkDerivation rec {
    pname = "vault-mcp-server";
    version = "0.2.0";
    src = pkgs.fetchzip {
      url = "https://releases.hashicorp.com/vault-mcp-server/${version}/vault-mcp-server_${version}_linux_amd64.zip";
      hash = "sha256-/IqVtE6xQ7LRPMJohX1imTlOg9mfG90SZDwAHXzpbSg=";
      stripRoot = false;
    };
    installPhase = ''
      mkdir -p $out/bin
      cp vault-mcp-server $out/bin/
      chmod +x $out/bin/vault-mcp-server
    '';
  };
in
{
  options.modules.vault-mcp-server = {
    enable = lib.mkEnableOption "Vault MCP server for OpenBao";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to bind the HTTP server to";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8282;
      description = "Port for the streamable-http transport";
    };

    vaultAddr = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8200";
      description = "OpenBao API address (localhost since it runs on the same host)";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the VAULT_TOKEN for MCP access";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.vault-mcp-server = {
      description = "Vault MCP Server (OpenBao)";
      after = [
        "openbao.service"
        "network-online.target"
      ];
      wants = [
        "openbao.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        VAULT_ADDR = cfg.vaultAddr;
      };

      script = ''
        export VAULT_TOKEN="$(cat $CREDENTIALS_DIRECTORY/mcp-token)"
        exec ${vault-mcp-server}/bin/vault-mcp-server streamable-http \
          --transport-host ${cfg.listenAddress} \
          --transport-port ${toString cfg.listenPort}
      '';

      serviceConfig = {
        DynamicUser = true;
        LoadCredential = "mcp-token:${cfg.tokenFile}";
        Restart = "on-failure";
        RestartSec = 5;
        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.listenPort ];
  };
}
