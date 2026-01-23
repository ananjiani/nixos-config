{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.modules.privacy;
in
{
  options.modules.privacy = {
    mullvadCustomDns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Custom DNS servers for Mullvad VPN (use dns.servers from lib/dns.nix)";
      example = lib.literalExpression "(import ../../lib/dns.nix).servers";
    };
  };

  config = {
    environment.systemPackages = with pkgs; [
      tor-browser
      mullvad-browser
      nitrokey-app2
      bitwarden-desktop
      bitwarden-cli
    ];

    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
      enableExcludeWrapper = true;
    };

    # Configure Mullvad custom DNS declaratively
    systemd.services.mullvad-custom-dns = lib.mkIf (cfg.mullvadCustomDns != [ ]) {
      description = "Configure Mullvad custom DNS servers";
      after = [ "mullvad-daemon.service" ];
      wants = [ "mullvad-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.mullvad
        pkgs.gnugrep
      ];
      script =
        let
          dnsServers = lib.concatStringsSep " " cfg.mullvadCustomDns;
          # For checking - one server per line in output
        in
        ''
          # Check if DNS is already configured correctly
          current=$(mullvad dns get 2>/dev/null || echo "")
          if echo "$current" | grep -q "Custom DNS: yes"; then
            # Check if all expected servers are present
            servers=$(echo "$current" | grep -E '^[0-9]+\.' || true)
            expected="${lib.concatStringsSep "\n" cfg.mullvadCustomDns}"
            if [ "$servers" = "$expected" ]; then
              echo "Mullvad DNS already configured correctly"
              exit 0
            fi
          fi

          # Wait for daemon and set DNS
          for i in $(seq 1 5); do
            if mullvad dns set custom ${dnsServers}; then
              echo "Mullvad DNS configured successfully"
              exit 0
            fi
            echo "Attempt $i failed, waiting..."
            sleep 3
          done
          echo "Warning: Could not configure Mullvad DNS"
          exit 0
        '';
    };

    hardware.nitrokey.enable = true;
  };
}
