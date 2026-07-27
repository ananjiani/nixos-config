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
  ntfyPluginRef = "f07462439b7dde0ac08ffe90d30661520037d561";
  ntfyPluginId = "cobanov.herdr-ntfysh";
  mirrorPluginId = "mirror";
  # Fully pin herdr-mirror source + prebuilt binary so activation never
  # downloads mutable GitHub release assets at deploy time.
  mirrorPluginSrc = pkgs.fetchFromGitHub {
    owner = "nikok6";
    repo = "herdr-mirror";
    rev = "f3340d38ac4edddfd80bc7d0942b88fd457f1eab";
    hash = "sha256-Qd805gn4pFGLUHB9d1b+wa9GmS7/StrUpQWBQNbUahs=";
  };
  mirrorPluginBin = pkgs.fetchurl {
    url = "https://github.com/nikok6/herdr-mirror/releases/download/v0.1.13/herdr-mirror-linux-x86_64";
    hash = "sha256-fewx/Voe4yEp89KtBGPcxsvQ7usBSIOpBAPSR39pQKU=";
  };
  mirrorPluginRoot = pkgs.runCommand "herdr-mirror-plugin" { } ''
    mkdir -p $out
    cp -a ${mirrorPluginSrc}/. $out/
    chmod -R u+w $out
    mkdir -p $out/target/release
    install -m 755 ${mirrorPluginBin} $out/target/release/herdr-mirror
  '';
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

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
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

  users = {
    # Keep the user manager alive for persistent agent sessions and user secrets.
    users.ammar = {
      linger = true;
      extraGroups = [ "hermes" ];
    };
    groups.hermes = { };
  };

  # Hermes Agent trial — native mode on existing ammar account (Codex OAuth).
  # Auth bootstrap after deploy: hermes auth add openai-codex
  services = {
    hermes-agent = {
      enable = true;
      user = "ammar";
      group = "hermes";
      createUser = false;
      addToSystemPackages = true;
      extraPackages = [ pkgs.openssh ];
      settings = {
        model = {
          provider = "openai-codex";
          default = "gpt-5.5";
        };
        terminal = {
          backend = "local";
          env_passthrough = [ ];
        };
        approvals = {
          mode = "manual";
          cron_mode = "deny";
        };
        security = {
          allow_lazy_installs = false;
          allow_private_urls = false;
        };
        code_execution = {
          mode = "strict";
        };
      };
    };
  };

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

      xdg.configFile = {
        "herdr/plugins/config/herdr.collie/.env".text = ''
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

        "herdr/plugins/config/cobanov.herdr-ntfysh/.env".text = ''
          HERDR_NTFY_SERVER=https://ntfy.dimensiondoor.xyz
          HERDR_NTFY_TOPIC=herdr
          HERDR_NTFY_NOTIFY_ON=done,blocked
          HERDR_NTFY_CLICK=https://collie.dimensiondoor.xyz
        '';

        "herdr-mirror/hosts.toml".text = ''
          autostart = true
          close_remote_on_local_close = false
          always_control = false

          [hosts.desktop]
          target = "ammars-pc.lan"
          prefix = "desktop"
          remote_bin = "/home/ammar/.nix-profile/bin/herdr"
        '';
      };

      home = {
        packages = [ pkgs.bun ];
        activation = {
          # Install pinned Collie plugin only when missing or at the wrong revision.
          installColliePlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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

          # Install pinned herdr-ntfysh plugin only when missing or at the wrong revision.
          installNtfyPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            export CGO_ENABLED=0
            export PATH="${
              lib.makeBinPath [
                herdrPkg
                pkgs.go
                pkgs.git
                pkgs.jq
                pkgs.coreutils
              ]
            }:$PATH"
            plugins_json="$HOME/.config/herdr/plugins.json"
            want_ref="${ntfyPluginRef}"
            have_ref=""
            if [ -f "$plugins_json" ]; then
              have_ref="$(jq -r --arg id "${ntfyPluginId}" \
                '.[] | select(.plugin_id == $id) | .source.resolved_commit // empty' \
                "$plugins_json" 2>/dev/null || true)"
            fi
            if [ "$have_ref" != "$want_ref" ]; then
              if ! run herdr plugin install cobanov/herdr-ntfysh --ref "$want_ref" --yes; then
                echo "warning: herdr-ntfysh plugin install failed (Go build); deploy continues without ntfy" >&2
              fi
            fi
          '';

          # Link Nix-pinned herdr-mirror plugin tree when plugin_root drifts.
          installMirrorPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            export PATH="${
              lib.makeBinPath [
                herdrPkg
                pkgs.openssh
                pkgs.jq
                pkgs.coreutils
              ]
            }:$PATH"
            plugins_json="$HOME/.config/herdr/plugins.json"
            want_root="${mirrorPluginRoot}"
            have_root=""
            if [ -f "$plugins_json" ]; then
              have_root="$(jq -r --arg id "${mirrorPluginId}" \
                '.[] | select(.plugin_id == $id) | .plugin_root // empty' \
                "$plugins_json" 2>/dev/null || true)"
            fi
            if [ "$have_root" != "$want_root" ]; then
              # Pause daemon first so mirrors/remote sessions stay open across relink.
              if [ -n "$have_root" ] && [ -x "$have_root/target/release/herdr-mirror" ]; then
                run "$have_root/target/release/herdr-mirror" pause 2>/dev/null || true
              fi
              if [ -n "$have_root" ]; then
                kind="$(jq -r --arg id "${mirrorPluginId}" \
                  '.[] | select(.plugin_id == $id) | .source.kind // empty' \
                  "$plugins_json" 2>/dev/null || true)"
                case "$kind" in
                  github)
                    run herdr plugin uninstall "${mirrorPluginId}" 2>/dev/null || true
                    ;;
                  *)
                    # Local link (or unknown): unlink first, fall back to uninstall.
                    if ! run herdr plugin unlink "${mirrorPluginId}" 2>/dev/null; then
                      run herdr plugin uninstall "${mirrorPluginId}" 2>/dev/null || true
                    fi
                    ;;
                esac
              fi
              if ! run herdr plugin link "$want_root"; then
                echo "warning: herdr-mirror plugin link failed; deploy continues without mirror" >&2
              else
                # Reload then resume daemon with the new pinned binary.
                if herdr status server >/dev/null 2>&1; then
                  herdr server reload-config 2>/dev/null || echo "warning: herdr server reload-config failed" >&2
                  if [ -x "$want_root/target/release/herdr-mirror" ]; then
                    run "$want_root/target/release/herdr-mirror" start 2>/dev/null \
                      || echo "warning: herdr-mirror start failed after relink" >&2
                  fi
                fi
              fi
            elif herdr status server >/dev/null 2>&1; then
              herdr server reload-config 2>/dev/null || echo "warning: herdr server reload-config failed" >&2
            fi
          '';
        };
      };

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
