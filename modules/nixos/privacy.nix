{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.modules.privacy;

  # Mullvad silently drops tunnel-unreachable (LAN) DNS servers from its
  # published list when any tunnel-reachable (public) server is present,
  # leaving wg0-mullvad's `~.` catch-all routing all DNS through the public
  # resolver and breaking AdGuard split-DNS. So this option must contain
  # ONLY RFC1918 (10/8, 172.16/12, 192.168/16) or ULA (fc00::/7) addresses.
  isPrivateIp =
    addr:
    lib.hasPrefix "10." addr
    || lib.hasPrefix "192.168." addr
    || lib.any (n: lib.hasPrefix "172.${toString n}." addr) (lib.range 16 31)
    || lib.hasPrefix "fc" addr
    || lib.hasPrefix "fd" addr;

  invalidDns = lib.filter (addr: !isPrivateIp addr) cfg.mullvadCustomDns;
in
{
  options.modules.privacy = {
    mullvadCustomDns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Custom DNS servers for Mullvad VPN. MUST contain only LAN
        (RFC1918 / ULA) addresses — never a public fallback. Mullvad filters
        tunnel-unreachable servers out of its published list when a
        tunnel-reachable server is present, and combined with wg0-mullvad's
        catch-all routing domain this routes all DNS through the public
        resolver and breaks split-DNS. Enforced by an assertion.
      '';
      example = lib.literalExpression ''[ "192.168.1.53" "192.168.1.1" ]'';
    };
  };

  config = {
    assertions = [
      {
        assertion = invalidDns == [ ];
        message = ''
          modules.privacy.mullvadCustomDns must contain only RFC1918
          (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) or ULA (fc00::/7)
          addresses. Public DNS servers are silently filtered out by Mullvad
          and break split-DNS for Tailscale login.
          Invalid entries: ${lib.concatStringsSep ", " invalidDns}
        '';
      }
    ];

    environment.systemPackages = with pkgs; [
      tor-browser
      mullvad-browser
      nitrokey-app2
    ];

    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
      enableExcludeWrapper = true;
    };

    # Lower wg0-mullvad MTU from mullvad's default 1380 to 1280. Default
    # black-holes large packets on paths with extra encapsulation past the
    # mullvad exit (e.g. SSH to codeberg — signature packet >1352B silently
    # dropped, PMTUD ICMP never returns). 1280 matches Tailscale and leaves
    # headroom. See docs/content/postmortems/ (MTU incidents). mullvad owns
    # wg0-mullvad so this can't be set via networking.wireguard.
    systemd.services.mullvad-mtu = {
      description = "Set Mullvad tunnel MTU to 1280";
      after = [ "mullvad-daemon.service" ];
      wants = [ "mullvad-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.mullvad ];
      script = ''
        for i in $(seq 1 5); do
          if mullvad tunnel set mtu 1280; then exit 0; fi
          sleep 3
        done
        echo "Warning: Could not set Mullvad MTU"
        exit 0
      '';
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
