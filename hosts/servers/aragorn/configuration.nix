# Aragorn - Devbox / homelab command center (Proxmox VM on gondor)
#
# Always-on sandbox for coding agents (pi, claude), reachable over
# Tailscale. Holds a ~/.dotfiles checkout and runs deploy-rs / heavy
# nix builds so the desktop doesn't have to.
{
  inputs,
  pkgs,
  lib,
  ...
}:

let
  lanHosts = import ../../../lib/hosts.nix;
  collieRef = "8c898a013d65fe1c33eb9b947d4d5e3b32eb936f";
  colliePluginId = "herdr.collie";
  collieLanIp = lanHosts.aragorn;
  collieLanPort = 8788;
  collieLoopbackPort = 8787;
  # k3s node LAN IPs that may reach the collie-lan-proxy socket
  collieSourceIps = [
    lanHosts.boromir
    lanHosts.samwise
    lanHosts.theoden
    lanHosts.rivendell
  ];
  herdrPkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ../../_profiles/server/configuration.nix
    ../../../modules/nixos/networking.nix
  ];

  networking = {
    hostName = "aragorn";

    # Accept collie-lan-proxy only from k3s nodes. Do not open the port broadly.
    firewall = {
      extraCommands = lib.concatMapStrings (src: ''
        iptables -A nixos-fw -p tcp -s ${src} -d ${collieLanIp} --dport ${toString collieLanPort} -j nixos-fw-accept
      '') collieSourceIps;
      extraStopCommands = lib.concatMapStrings (src: ''
        iptables -D nixos-fw -p tcp -s ${src} -d ${collieLanIp} --dport ${toString collieLanPort} -j nixos-fw-accept 2>/dev/null || true
      '') collieSourceIps;
    };
  };

  # Plain tailnet client — not routing infrastructure
  modules = {
    tailscale = {
      exitNode = false;
      subnetRoutes = [ ];
    };

    # API keys consumed by the Pi and Claude wrapper configurations.
    vault-agent.secrets = {
      kimi_code_api_key = {
        path = "secret/llm/keys";
        field = "kimi-code-api-key";
        owner = "ammar";
      };
      zai_api_key = {
        path = "secret/llm/keys";
        field = "zai-api-key";
        owner = "ammar";
      };
      tavily_api_key = {
        path = "secret/llm/keys";
        field = "tavily-api-key";
        owner = "ammar";
      };
      opencode_api_key = {
        path = "secret/llm/keys";
        field = "opencode-api-key";
        owner = "ammar";
      };
    };
  };

  # Keep the user manager alive for persistent agent sessions and user secrets.
  users.users.ammar.linger = true;

  # Dev/agent tooling on top of the minimal shared server home profile.
  # Function form so lib.hm (home-manager) is in scope for activation scripts.
  home-manager.users.ammar =
    {
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.stylix.homeModules.stylix
        inputs.sops-nix.homeManagerModules.sops
        ../../../modules/home/dev/pi-coding-agent.nix
        ../../../modules/home/dev/claude-code.nix
        ../../../modules/home/dev/nix-direnv.nix
        ../../../modules/home/dev/tea.nix
        ../../../modules/home/dev/lang/python.nix
        ../../../modules/home/dev/lang/nixlang.nix
        ../../../modules/home/dev/nix-index.nix
        ../../../modules/home/dev/programs.nix
      ];

      sops = {
        age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
        defaultSopsFile = ../../../secrets/secrets.yaml;
        defaultSymlinkPath = "/run/user/1000/secrets";
        defaultSecretsMountPoint = "/run/user/1000/secrets.d";
      };

      # Pi consumes config.lib.stylix.colors, but a headless server must not
      # activate Stylix's KDE/dconf targets.
      stylix = {
        enable = false;
        base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-soft.yaml";
        polarity = "dark";
      };

      home.packages = [
        pkgs.bun
      ];

      xdg.configFile."herdr/plugins/config/herdr.collie/.env".text = ''
        COLLIE_PORT=${toString collieLoopbackPort}
        COLLIE_HOST=127.0.0.1
        COLLIE_SKIP_SERVE=1
        COLLIE_PUBLIC_URL=https://collie.dimensiondoor.xyz
        COLLIE_PUBLIC_HOSTS=collie.dimensiondoor.xyz
        COLLIE_ALLOWED_ORIGINS=https://collie.dimensiondoor.xyz
        COLLIE_MULTI_SESSION=on
        # Write gate only — firewall remains the read/confidentiality boundary.
        COLLIE_DEVICE_HEADER=X-authentik-uid
        COLLIE_DEVICE_ALLOWLIST=22fb6423c4bb0c1f65d8720b50cbfcfd993da9b47bd0375bd007b1051412d07f
      '';

      # Install pinned Collie plugin only when missing or at the wrong revision.
      home.activation.installColliePlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${
          lib.makeBinPath [
            herdrPkg
            pkgs.bun
            pkgs.git
            pkgs.jq
            pkgs.coreutils
          ]
        }:$PATH"
        plugins_json="$HOME/.config/herdr/plugins.json"
        want_ref="${collieRef}"
        have_ref=""
        if [ -f "$plugins_json" ]; then
          have_ref="$(jq -r --arg id "${colliePluginId}" \
            '.[] | select(.plugin_id == $id) | .source.resolved_commit // empty' \
            "$plugins_json" 2>/dev/null || true)"
        fi
        if [ "$have_ref" != "$want_ref" ]; then
          if ! run herdr plugin install AltanS/collie --ref "$want_ref" --yes; then
            echo "warning: collie plugin install failed (GitHub/Bun); deploy continues without collie" >&2
          fi
        fi
      '';

      systemd.user = {
        services = {
          # Named collie-bridge so it cannot collide with upstream plugin collie.service.
          collie-bridge = {
            Unit = {
              Description = "Collie Herdr bridge (loopback)";
              After = [ "default.target" ];
              StartLimitIntervalSec = 0;
            };
            Service = {
              Type = "simple";
              Environment = [
                "HERDR_SOCKET_PATH=%h/.config/herdr/herdr.sock"
                "HERDR_PLUGIN_CONFIG_DIR=%h/.config/herdr/plugins/config/herdr.collie"
              ];
              EnvironmentFile = "%h/.config/herdr/plugins/config/herdr.collie/.env";
              # Resolve plugin_root from plugins.json at start so reinstalls don't
              # need a unit rewrite.
              ExecStart = toString (
                pkgs.writeShellScript "collie-bridge-start" ''
                  set -euo pipefail
                  export PATH="${
                    lib.makeBinPath [
                      pkgs.bun
                      pkgs.jq
                      pkgs.coreutils
                    ]
                  }:$PATH"
                  plugins_json="$HOME/.config/herdr/plugins.json"
                  plugin_root="$(jq -r --arg id "${colliePluginId}" \
                    '.[] | select(.plugin_id == $id) | .plugin_root // empty' \
                    "$plugins_json")"
                  if [ -z "$plugin_root" ] || [ ! -d "$plugin_root" ]; then
                    echo "collie-bridge: plugin_root for ${colliePluginId} missing in $plugins_json" >&2
                    exit 1
                  fi
                  cd "$plugin_root"
                  exec bun run "$plugin_root/bridge/index.ts"
                ''
              );
              Restart = "on-failure";
              RestartSec = 5;
              NoNewPrivileges = true;
              PrivateTmp = true;
            };
            Install = {
              WantedBy = [ "default.target" ];
            };
          };

          collie-lan-proxy = {
            Unit = {
              Description = "Proxy collie LAN socket to loopback bridge";
              Requires = [
                "collie-bridge.service"
                "collie-lan-proxy.socket"
              ];
              After = [
                "collie-bridge.service"
                "collie-lan-proxy.socket"
              ];
            };
            Service = {
              Type = "simple";
              ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString collieLoopbackPort}";
              PrivateTmp = true;
              NoNewPrivileges = true;
            };
          };
        };

        sockets.collie-lan-proxy = {
          Unit = {
            Description = "LAN listen socket for Collie (${collieLanIp}:${toString collieLanPort})";
          };
          Socket = {
            ListenStream = "${collieLanIp}:${toString collieLanPort}";
            Accept = false;
            FreeBind = true;
          };
          Install = {
            WantedBy = [ "sockets.target" ];
          };
        };
      };
    };
}
