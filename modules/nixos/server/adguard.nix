# AdGuard Home - Network-wide DNS ad blocker
#
# Plain configuration file - importing this enables AdGuard Home.
# Replicates the k8s AdGuard configuration for consistency.
_: {
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
        enable_dnssec = false;

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
      ];

      dhcp = {
        enabled = false;
      };

      filtering = {
        blocking_mode = "default";
        filtering_enabled = true;
        protection_enabled = true;

        rewrites = [
          # Local infrastructure
          {
            domain = "router.lan";
            answer = "192.168.1.1";
          }
          {
            domain = "gondor.lan";
            answer = "192.168.1.20";
          }
          {
            domain = "boromir.lan";
            answer = "192.168.1.21";
          }
          {
            domain = "faramir.lan";
            answer = "192.168.1.22";
          }
          {
            domain = "the-shire.lan";
            answer = "192.168.1.23";
          }
          {
            domain = "rohan.lan";
            answer = "192.168.1.24";
          }
          {
            domain = "frodo.lan";
            answer = "192.168.1.25";
          }
          {
            domain = "samwise.lan";
            answer = "192.168.1.26";
          }
          {
            domain = "theoden.lan";
            answer = "192.168.1.27";
          }
          {
            domain = "pippin.lan";
            answer = "192.168.1.28";
          }
          {
            domain = "ammars-pc.lan";
            answer = "192.168.1.50";
          }

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
            answer = "192.168.1.52";
          }
          {
            domain = "cliproxy.lan";
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
            domain = "scriberr.dimensiondoor.xyz";
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
            domain = "ntfy.dimensiondoor.xyz";
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
        persistent = [ ];
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
}
