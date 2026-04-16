# AdGuard Home - Network-wide DNS ad blocker
#
# Replicates the k8s AdGuard configuration for consistency.
{ config, lib, ... }:

let
  lanHosts = import ../../../lib/hosts.nix;
in
{
  options.modules.adguard.enable = lib.mkEnableOption "AdGuard Home DNS ad blocker";

  config = lib.mkIf config.modules.adguard.enable {
    services.adguardhome = {
      enable = true;
      host = "0.0.0.0";
      port = 3000;
      mutableSettings = false;

      settings = {
        schema_version = 29;

        http = {
          pprof = {
            port = 6060;
            enabled = false;
          };
          address = "0.0.0.0:3000";
          session_ttl = "720h";
        };

        users = [ ];
        auth_attempts = 5;
        block_auth_min = 15;
        language = "en";
        theme = "auto";

        dns = {
          bind_hosts = [ "0.0.0.0" ];
          port = 53;
          anonymize_client_ip = false;
          ratelimit = 0;
          refuse_any = true;

          upstream_dns = [
            "9.9.9.9"
            "194.242.2.2"
          ];

          bootstrap_dns = [
            "9.9.9.9"
            "194.242.2.2"
          ];

          upstream_mode = "load_balance";
          fastest_timeout = "1s";
          cache_size = 4194304;
          enable_dnssec = true;

          edns_client_subnet = {
            custom_ip = "";
            enabled = false;
            use_custom = false;
          };

          max_goroutines = 300;
          handle_ddr = true;
          hostsfile_enabled = true;
          serve_plain_dns = true;
        };

        tls = {
          enabled = false;
        };

        querylog = {
          enabled = true;
          file_enabled = true;
          interval = "24h";
          size_memory = 1000;
        };

        statistics = {
          enabled = true;
          interval = "24h";
        };

        filters = [
          {
            enabled = true;
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
            name = "AdGuard DNS filter";
            id = 1;
          }
          {
            enabled = true;
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
            name = "AdAway Default Blocklist";
            id = 2;
          }
          {
            enabled = true;
            url = "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV-AGH.txt";
            name = "Perflyst Smart TV Blocklist";
            id = 3;
          }
          {
            enabled = true;
            url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.txt";
            name = "HaGeZi Pro";
            id = 4;
          }
          {
            enabled = true;
            url = "https://big.oisd.nl/";
            name = "OISD Big";
            id = 5;
          }
          {
            enabled = true;
            url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/tif.medium.txt";
            name = "HaGeZi Threat Intelligence Feeds (Medium)";
            id = 6;
          }
          {
            enabled = true;
            url = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareAdGuardHome.txt";
            name = "Dandelion Sprout's Anti-Malware";
            id = 7;
          }
          {
            enabled = true;
            url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/native.apple.txt";
            name = "HaGeZi Apple Native Tracking";
            id = 8;
          }
        ];

        dhcp = {
          enabled = false;
        };

        filtering = {
          blocking_mode = "default";
          filtering_enabled = true;
          protection_enabled = true;

          # Chromecast telemetry (scoped to device IPs only)
          user_rules = [
            "||firebaselogging-pa.googleapis.com^$client='192.168.1.10'|'192.168.1.11'"
            "||firebaselogging.googleapis.com^$client='192.168.1.10'|'192.168.1.11'"
            "||firebaseinstallations.googleapis.com^$client='192.168.1.10'|'192.168.1.11'"
            "||firebase-settings.crashlytics.com^$client='192.168.1.10'|'192.168.1.11'"
            "||crashlyticsreports-pa.googleapis.com^$client='192.168.1.10'|'192.168.1.11'"
            "||app-measurement.com^$client='192.168.1.10'|'192.168.1.11'"

            # Global ad blocking (safe, ensures these aren't overridden by allowlists)
            "||adservice.google.*^$important"
            "||pagead2.googlesyndication.com^$important"
            "||googleadservices.com^$important"

            # Prevent DoH bypass (blocks resolution of DNS-over-HTTPS endpoints)
            "||dns.google^$important"
            "||dns.google.com^$important"
            "||dns64.dns.google^$important"
            "||cloudflare-dns.com^$important"
            "||mozilla.cloudflare-dns.com^$important"
            "||doh.opendns.com^$important"
            "||dns.adguard-dns.com^$important"
          ];

          rewrites =
            # Local infrastructure (generated from lib/hosts.nix)
            lib.mapAttrsToList (name: ip: {
              domain = "${name}.lan";
              answer = ip;
            }) lanHosts
            ++ [
              # K8s services (Traefik ingress at 192.168.1.52)
              {
                domain = "ts.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "auth.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "immich.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "ai.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "home.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "bifrost.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "ha.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "git.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "adguard.lan";
                answer = "192.168.1.53"; # keepalived VIP (AdGuard UI on port 3000)
              }
              {
                domain = "cliproxy.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "searxng.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "stremio.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "comet.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "prowlarr.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "attic.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "lobe.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "clawd.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "ntfy.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "voicemail.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "voicemail.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "persona.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "mcp.persona.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "grafana.dimensiondoor.xyz";
                answer = "192.168.1.52";
              }
              {
                domain = "grafana.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "holmes.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "bifrost.lan";
                answer = "192.168.1.52";
              }
              {
                domain = "zot.lan";
                answer = "192.168.1.56";
              }

              # Wyoming Whisper (Keepalived VIP - rohan primary, boromir backup)
              {
                domain = "whisper.lan";
                answer = "192.168.1.54";
              }

              # Forgejo SSH
              {
                domain = "ssh.git.dimensiondoor.xyz";
                answer = "192.168.1.55";
              }
            ];
        };

        clients = {
          runtime_sources = {
            whois = true;
            arp = true;
            rdns = true;
            dhcp = true;
            hosts = true;
          };
          persistent = [
            {
              name = "Chromecast 4K";
              ids = [
                "192.168.1.10" # WiFi
                "192.168.1.11" # Ethernet
              ];
              tags = [ "device_tv" ];
              use_global_settings = true;
              use_global_blocked_services = true;
              filtering_enabled = true;
              safebrowsing_enabled = false;
              parental_enabled = false;
              safe_search = {
                enabled = false;
              };
            }
          ];
        };

        log = {
          enabled = true;
          max_size = 100;
          max_age = 3;
        };
      };
    };

    networking.firewall = {
      allowedTCPPorts = [
        53
        3000
      ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
