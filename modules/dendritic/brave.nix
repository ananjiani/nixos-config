# Dendritic Brave Browser Module
# Declarative privacy-focused configuration for Brave browser
# Following Privacy Guides recommendations with configurable debloat options
#
# NOTE: Brave on Linux only reads policies from /etc/brave/policies/managed/
# This is a NixOS-only module - no Home Manager needed.
_:

{
  # NixOS module - installs Brave and writes policies to /etc/brave/policies/managed/
  flake.aspects.brave.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.programs.brave;

      # DNS over HTTPS provider URLs
      dohProviders = {
        quad9 = "https://dns.quad9.net/dns-query";
        cloudflare = "https://cloudflare-dns.com/dns-query";
        adguard = "https://dns.adguard-dns.com/dns-query";
        mullvad = "https://doh.mullvad.net/dns-query";
      };

      # Get DoH URL based on provider selection
      dohUrl =
        if cfg.doh.provider == "custom" then
          cfg.doh.customUrl
        else
          dohProviders.${cfg.doh.provider} or dohProviders.quad9;

      # Permission values: 1 = allow, 2 = block, 3 = ask
      permissionValue =
        setting:
        if setting == "allow" then
          1
        else if setting == "block" then
          2
        else
          3; # "ask"

      # Generate policy attrset
      policies = {
        # === Feature Toggles (Debloat) ===
        BraveRewardsDisabled = !cfg.features.rewards;
        BraveWalletDisabled = !cfg.features.wallet;
        BraveVPNDisabled = !cfg.features.vpn;
        BraveAIChatEnabled = cfg.features.aiChat;
        BraveNewsDisabled = !cfg.features.news;
        BraveTalkDisabled = !cfg.features.talk;
        TorDisabled = !cfg.features.tor;
        SyncDisabled = !cfg.features.sync;
        BraveSpeedreaderEnabled = cfg.features.speedreader;
        BraveWaybackMachineEnabled = cfg.features.waybackMachine;
        BravePlaylistEnabled = cfg.features.playlist;

        # === Telemetry (Privacy Guides: all disabled) ===
        BraveP3AEnabled = cfg.telemetry.p3a;
        BraveStatsPingEnabled = cfg.telemetry.dailyPing;
        BraveWebDiscoveryEnabled = cfg.telemetry.webDiscovery;
        MetricsReportingEnabled = cfg.telemetry.diagnostics;

        # === Autofill ===
        PasswordManagerEnabled = cfg.autofill.passwords;
        AutofillAddressEnabled = cfg.autofill.addresses;
        AutofillCreditCardEnabled = cfg.autofill.creditCards;

        # === Permissions (Privacy Guides: restrict by default) ===
        DefaultGeolocationSetting = permissionValue cfg.permissions.geolocation;
        DefaultNotificationsSetting = permissionValue cfg.permissions.notifications;

        # === Misc Privacy Settings ===
        TranslateEnabled = cfg.misc.translate;
        BackgroundModeEnabled = cfg.misc.backgroundMode;
      }
      # DNS over HTTPS (conditional)
      // lib.optionalAttrs cfg.doh.enable {
        DnsOverHttpsMode = cfg.doh.mode;
        DnsOverHttpsTemplates = dohUrl;
      }
      # WebRTC IP leak protection
      // lib.optionalAttrs cfg.webrtc.disableNonProxiedUdp {
        WebRtcIPHandling = "disable_non_proxied_udp";
      }
      # Additional policies from extraPolicies
      // cfg.extraPolicies;

      policiesJson = builtins.toJSON policies;
    in
    {
      options.programs.brave = {
        enable = lib.mkEnableOption "Brave browser with declarative privacy configuration";

        # === Feature Toggles ===
        features = {
          rewards = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave Rewards (BAT cryptocurrency)";
          };

          wallet = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave Wallet (cryptocurrency wallet)";
          };

          vpn = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave VPN";
          };

          aiChat = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave Leo AI Chat";
          };

          news = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave News";
          };

          talk = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave Talk (video conferencing)";
          };

          tor = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Tor integration in private windows";
          };

          sync = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Brave Sync (syncs bookmarks, extensions, etc.)";
          };

          speedreader = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave Speedreader for distraction-free reading";
          };

          waybackMachine = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Wayback Machine integration";
          };

          playlist = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Brave Playlist";
          };
        };

        # === Telemetry Settings ===
        telemetry = {
          p3a = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Privacy-Preserving Product Analytics (P3A)";
          };

          dailyPing = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable daily usage ping to Brave";
          };

          diagnostics = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable diagnostic reports";
          };

          webDiscovery = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Web Discovery Project (WDAP)";
          };
        };

        # === DNS over HTTPS ===
        doh = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable DNS over HTTPS";
          };

          mode = lib.mkOption {
            type = lib.types.enum [
              "off"
              "automatic"
              "secure"
            ];
            default = "secure";
            description = ''
              DNS over HTTPS mode:
              - off: Don't use DoH
              - automatic: Use DoH if available, fallback to system DNS
              - secure: Always use DoH, fail if unavailable
            '';
          };

          provider = lib.mkOption {
            type = lib.types.enum [
              "quad9"
              "cloudflare"
              "adguard"
              "mullvad"
              "custom"
            ];
            default = "quad9";
            description = "DNS over HTTPS provider (Quad9 recommended by Privacy Guides)";
          };

          customUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Custom DoH URL (used when provider is 'custom')";
            example = "https://dns.example.com/dns-query";
          };
        };

        # === Permissions ===
        permissions = {
          geolocation = lib.mkOption {
            type = lib.types.enum [
              "allow"
              "block"
              "ask"
            ];
            default = "block";
            description = "Default geolocation permission (Privacy Guides: block)";
          };

          notifications = lib.mkOption {
            type = lib.types.enum [
              "allow"
              "block"
              "ask"
            ];
            default = "block";
            description = "Default notifications permission (Privacy Guides: block)";
          };
        };

        # === Autofill ===
        autofill = {
          addresses = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable address autofill";
          };

          creditCards = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable credit card autofill";
          };

          passwords = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable built-in password manager (recommend external manager instead)";
          };
        };

        # === WebRTC ===
        webrtc = {
          disableNonProxiedUdp = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Disable non-proxied UDP to prevent IP leaks (Privacy Guides recommendation)";
          };
        };

        # === Miscellaneous ===
        misc = {
          translate = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable translation feature";
          };

          backgroundMode = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Continue running background apps when browser is closed";
          };
        };

        # === Extra Policies ===
        extraPolicies = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = ''
            Additional Chromium/Brave policies to set.
            See: https://support.brave.com/hc/en-us/articles/360039248271-Group-Policy
          '';
          example = lib.literalExpression ''
            {
              DefaultSearchProviderEnabled = true;
              DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
            }
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Install Brave browser
        environment.systemPackages = [ pkgs.brave ];

        # Write policies to /etc/brave/policies/managed/policies.json
        # This is the only location Brave reads on Linux
        environment.etc."brave/policies/managed/policies.json" = {
          text = policiesJson;
          mode = "0644";
        };
      };
    };
}
