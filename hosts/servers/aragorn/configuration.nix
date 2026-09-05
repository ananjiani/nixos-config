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
  hermesLanPort = 9119;
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

  desktopHost = "ammars-pc.lan";
  desktopMac = "30:c5:99:26:f4:c5";
  desktopBroadcast = "192.168.1.255";
  desktopIdentity = "/home/ammar/.ssh/id_ed25519";
  desktopHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINnidnIXwZdzKVv6fZZmoAOStpX5ZQdHjpvH6cR4yKjA";
  ntfyUrl = "https://ntfy.dimensiondoor.xyz/monitoring";
  repoHttps = "https://codeberg.org/ananjiani/infra.git";
  statusApi = "https://codeberg.org/api/v1/repos/ananjiani/infra/commits";
  stateDir = "/var/lib/desktop-deploy";
  metricsDir = "/var/lib/desktop-deploy/metrics";

  # Piped to remote bash -s over SSH as root; shebang is ignored, no Aragorn
  # store paths. Pin the remote PATH: non-interactive ssh commands get a
  # minimal environment and must find pgrep/systemctl/runuser/git.
  ammarsPcSafetyCheck = pkgs.writeText "ammars-pc-deploy-safety.sh" ''
    set -eu
    export PATH=/run/current-system/sw/bin:/usr/bin:/bin

    sha=''${1:-}
    echo "$sha" | grep -qxE '[0-9a-f]{40}' || {
      echo "safety: invalid sha" >&2
      echo dirty
      exit 12
    }

    # The niri-hdr fork keeps the upstream `niri` binary name.
    if pgrep -u ammar -x niri >/dev/null && ! pgrep -u ammar -x swaylock >/dev/null; then
      echo "safety: niri session is active and unlocked" >&2
      echo active
      exit 10
    fi

    for unit in nix-optimise.service nix-gc.service; do
      if systemctl is-active --quiet "$unit"; then
        echo "safety: $unit is active" >&2
        echo maintenance
        exit 11
      fi
    done

    repo=/home/ammar/.dotfiles
    if [ ! -d "$repo/.git" ]; then
      echo "safety: missing $repo/.git" >&2
      echo dirty
      exit 12
    fi

    export GIT_TERMINAL_PROMPT=0

    status=$(runuser -u ammar -- git -C "$repo" status --porcelain --untracked-files=all)
    if [ -n "$status" ]; then
      echo "safety: checkout is dirty" >&2
      echo dirty
      exit 12
    fi

    branch=$(runuser -u ammar -- git -C "$repo" rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "main" ]; then
      echo "safety: branch is $branch, not main" >&2
      echo dirty
      exit 12
    fi

    if ! runuser -u ammar -- git -C "$repo" fetch --quiet ${repoHttps} refs/heads/main; then
      echo "safety: git fetch failed" >&2
      echo maintenance
      exit 11
    fi

    fetched=$(runuser -u ammar -- git -C "$repo" rev-parse FETCH_HEAD)
    if [ "$fetched" != "$sha" ]; then
      echo "safety: FETCH_HEAD $fetched != $sha" >&2
      echo dirty
      exit 12
    fi

    if ! runuser -u ammar -- git -C "$repo" merge-base --is-ancestor HEAD "$sha"; then
      echo "safety: HEAD cannot fast-forward to $sha" >&2
      echo dirty
      exit 12
    fi

    if ! runuser -u ammar -- git -C "$repo" merge --ff-only --quiet "$sha"; then
      echo "safety: ff-only merge failed" >&2
      echo dirty
      exit 12
    fi

    echo ok
  '';

  ammarsPcDeploy = pkgs.writeShellApplication {
    name = "ammars-pc-deploy";
    # SC2029: the marker SSH command intentionally expands $sha/$marker on
    # the client ($sha is validated [0-9a-f]{40} first). SC2329: marker_clear
    # runs via the EXIT trap.
    excludeShellChecks = [
      "SC2029"
      "SC2329"
    ];
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.gnugrep
      pkgs.jq
      pkgs.nix
      pkgs.openssh
      pkgs.util-linux
      pkgs.wakeonlan
      inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
    text = ''
      set -euo pipefail

      STATE=${stateDir}
      METRICS=${metricsDir}
      IDENTITY=${desktopIdentity}
      HOST=${desktopHost}
      MAC=${desktopMac}
      BCAST=${desktopBroadcast}
      NTFY=${ntfyUrl}
      REPO=${repoHttps}
      STATUS_API=${statusApi}
      SAFETY=${ammarsPcSafetyCheck}
      RESULTS=(success woke_success active wake_failed dirty maintenance failure ignored)
      # One array element per ssh option, expanded as "''${SSH_OPTS[@]}" so
      # the shell never re-splits or globs an option. deploy-rs takes one
      # space-joined string (it splits on spaces itself), hence "''${SSH_OPTS[*]}".
      SSH_OPTS=(
        -o BatchMode=yes
        -o IdentitiesOnly=yes
        -o IdentityAgent=none
        -o PreferredAuthentications=publickey
        -o IdentityFile=${desktopIdentity}
        -o StrictHostKeyChecking=yes
        -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts
        -o GlobalKnownHostsFile=/dev/null
        -o ConnectTimeout=10
      )

      mkdir -p "$STATE" "$METRICS"
      exec 9>"$STATE/lock"
      if ! flock -n 9; then
        echo "ammars-pc-deploy: overlap, lock held" >&2
        exit 0
      fi

      now() { date +%s; }
      read_file() { [ -f "$1" ] && cat "$1" || true; }

      write_metrics() {
        local pending=$1 result=$2 revision=$3
        local pending_since last_attempt last_success_ts tmp r val
        pending_since=$(read_file "$STATE/pending-since")
        last_attempt=$(read_file "$STATE/last-attempt")
        last_success_ts=$(read_file "$STATE/last-success-ts")
        [ "$pending" = 1 ] || pending_since=0
        : "''${pending_since:=0}"
        : "''${last_attempt:=0}"
        : "''${last_success_ts:=0}"

        tmp=$(mktemp "$METRICS/ammars-pc-deploy.prom.XXXXXX")
        {
          echo "# HELP ammars_pc_deploy_pending 1 if a newer main SHA is waiting"
          echo "# TYPE ammars_pc_deploy_pending gauge"
          echo "ammars_pc_deploy_pending $pending"
          echo "# HELP ammars_pc_deploy_pending_since_timestamp_seconds Unix time the pending SHA was first seen"
          echo "# TYPE ammars_pc_deploy_pending_since_timestamp_seconds gauge"
          echo "ammars_pc_deploy_pending_since_timestamp_seconds $pending_since"
          echo "# HELP ammars_pc_deploy_last_attempt_timestamp_seconds Unix time of the last pending-release attempt"
          echo "# TYPE ammars_pc_deploy_last_attempt_timestamp_seconds gauge"
          echo "ammars_pc_deploy_last_attempt_timestamp_seconds $last_attempt"
          echo "# HELP ammars_pc_deploy_last_success_timestamp_seconds Unix time of the last successful desktop deploy"
          echo "# TYPE ammars_pc_deploy_last_success_timestamp_seconds gauge"
          echo "ammars_pc_deploy_last_success_timestamp_seconds $last_success_ts"
          echo "# HELP ammars_pc_deploy_result One-hot last desktop-deploy result"
          echo "# TYPE ammars_pc_deploy_result gauge"
          for r in "''${RESULTS[@]}"; do
            val=0
            [ "$r" = "$result" ] && val=1
            echo "ammars_pc_deploy_result{result=\"$r\"} $val"
          done
          if [ -n "$revision" ]; then
            echo "# HELP ammars_pc_deploy_revision_info SHA this controller last processed"
            echo "# TYPE ammars_pc_deploy_revision_info gauge"
            echo "ammars_pc_deploy_revision_info{revision=\"$revision\"} 1"
          fi
        } >"$tmp"
        chmod 644 "$tmp"
        mv -f "$tmp" "$METRICS/ammars-pc-deploy.prom"
      }

      notify() {
        local result=$1 sha=$2
        local short title body tags priority
        short="''${sha:0:8}"
        case "$result" in
          success)
            title="ammars-pc deployed $short"
            body="NixOS + Home Manager switched to $short."
            tags="white_check_mark"
            priority="default"
            ;;
          woke_success)
            title="ammars-pc woke and deployed $short"
            body="Woke the PC, then switched NixOS + Home Manager to $short."
            tags="white_check_mark"
            priority="default"
            ;;
          active)
            title="ammars-pc skipped: session unlocked"
            body="niri was unlocked. Did not deploy $short. Still pending."
            tags="warning"
            priority="4"
            ;;
          wake_failed)
            title="ammars-pc skipped: wake failed"
            body="PC did not wake. Did not deploy $short. Still pending."
            tags="warning"
            priority="4"
            ;;
          dirty)
            title="ammars-pc skipped: dirty checkout"
            body="Local git is dirty or not on main. Did not deploy $short. Still pending."
            tags="warning"
            priority="4"
            ;;
          maintenance)
            title="ammars-pc skipped: CI or maintenance"
            body="Buildbot not green, or nix-gc/optimise is running. Did not deploy $short. Still pending."
            tags="warning"
            priority="4"
            ;;
          failure)
            title="ammars-pc deploy failed $short"
            body="deploy-rs failed or rolled back on $short. Still pending."
            tags="rotating_light"
            priority="5"
            ;;
          ignored)
            title="ammars-pc skipped: no desktop changes"
            body="Only docs/ or k8s/ changed. Did not wake or deploy $short."
            tags="information_source"
            priority="default"
            ;;
          *)
            return 0
            ;;
        esac
        if ! curl --config /run/secrets/desktop-ntfy-curl-config \
          -fsS -o /dev/null --max-time 15 \
          -H "Title: $title" \
          -H "Tags: $tags" \
          -H "Priority: $priority" \
          -d "$body" \
          "$NTFY"; then
          echo "ammars-pc-deploy: ntfy send failed; metrics still written" >&2
        fi
      }

      finish() {
        local result=$1 sha=$2 pending=$3 code=$4
        echo "ammars-pc-deploy: result=$result sha=$sha pending=$pending" >&2
        echo "$result" >"$STATE/last-result"
        write_metrics "$pending" "$result" "$sha"
        notify "$result" "$sha"
        exit "$code"
      }

      ssh_ok() {
        ssh "''${SSH_OPTS[@]}" "root@$HOST" true
      }

      if [ ! -r "$IDENTITY" ]; then
        echo "ammars-pc-deploy: prerequisite missing: $IDENTITY" >&2
        echo "ammars-pc-deploy: create the Aragorn ed25519 key and keep it authorized on ammars-pc" >&2
        exit 1
      fi

      line=$(git ls-remote --exit-code "$REPO" refs/heads/main)
      sha="''${line%%[[:space:]]*}"
      echo "$sha" | grep -qxE '[0-9a-f]{40}' || {
        echo "ammars-pc-deploy: invalid main sha: $sha" >&2
        exit 1
      }

      last_success=$(read_file "$STATE/last-success")
      last_ignored=$(read_file "$STATE/last-ignored")
      if [ "$sha" = "$last_success" ] || [ "$sha" = "$last_ignored" ]; then
        echo "ammars-pc-deploy: $sha already handled" >&2
        write_metrics 0 "$(read_file "$STATE/last-result")" "$sha"
        exit 0
      fi

      if [ "$(read_file "$STATE/pending")" = "$sha" ]; then
        :
      else
        printf '%s\n' "$sha" >"$STATE/pending"
        now >"$STATE/pending-since"
      fi
      now >"$STATE/last-attempt"

      # Latest buildbot/nix-build status for this SHA must be a success; a
      # stale older success must not satisfy a newer pending/failed run.
      # Both paths route through finish() so metrics/ntfy are final, unlike
      # a bare exit.
      if ! status_json=$(curl -fsS --max-time 30 "$STATUS_API/$sha/status"); then
        echo "ammars-pc-deploy: codeberg status query failed" >&2
        finish failure "$sha" 1 1
      fi
      if ! printf '%s' "$status_json" | jq -e --arg ctx buildbot/nix-build '
          .statuses
          | map(select(.context == $ctx))
          | sort_by(.id)
          | last
          | .status == "success"
        ' >/dev/null; then
        # CI still pending/failed for this SHA: a maintenance skip — the
        # release stays pending and is retried at the next nightly window.
        echo "ammars-pc-deploy: $sha not green on buildbot/nix-build yet; staying pending, no WOL" >&2
        finish maintenance "$sha" 1 0
      fi

      # Conservative pre-WOL path filter: skip wake/deploy when every path
      # changed since last-success is under docs/ or k8s/. Fail open on any
      # classification error, empty last-success, or empty diff.
      paths_relevant() {
        local base=$1 head=$2
        local repo=$STATE/repository
        local paths path
        if [ -z "$base" ]; then
          echo "ammars-pc-deploy: no last-success; cannot classify, deploying" >&2
          return 0
        fi
        mkdir -p "$repo"
        if [ ! -d "$repo/.git" ] && [ ! -f "$repo/HEAD" ]; then
          if ! git -C "$repo" init --bare >/dev/null 2>&1; then
            echo "ammars-pc-deploy: classification failed (git init); deploying" >&2
            return 0
          fi
        fi
        if ! git -C "$repo" fetch --prune "$REPO" "+refs/heads/main:refs/heads/main" >/dev/null 2>&1; then
          echo "ammars-pc-deploy: classification failed (git fetch); deploying" >&2
          return 0
        fi
        if ! git -C "$repo" cat-file -e "$base^{commit}" 2>/dev/null \
          || ! git -C "$repo" cat-file -e "$head^{commit}" 2>/dev/null; then
          echo "ammars-pc-deploy: classification failed (missing commit); deploying" >&2
          return 0
        fi
        if ! paths=$(git -C "$repo" diff --name-only "$base" "$head" 2>/dev/null); then
          echo "ammars-pc-deploy: classification failed (git diff); deploying" >&2
          return 0
        fi
        if [ -z "$paths" ]; then
          echo "ammars-pc-deploy: empty diff vs last-success; deploying" >&2
          return 0
        fi
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          case "$path" in
            docs/* | k8s/*) ;;
            *)
              return 0
              ;;
          esac
        done <<<"$paths"
        return 1
      }

      if ! paths_relevant "$last_success" "$sha"; then
        echo "ammars-pc-deploy: $sha docs/k8s-only; ignoring" >&2
        printf '%s\n' "$sha" >"$STATE/last-ignored"
        rm -f "$STATE/pending" "$STATE/pending-since"
        finish ignored "$sha" 0 0
      fi

      woke=0
      if ! ssh_ok; then
        echo "ammars-pc-deploy: sending WOL to $MAC" >&2
        if ! wakeonlan -i "$BCAST" "$MAC"; then
          finish wake_failed "$sha" 1 0
        fi
        woke=1
        ok=0
        for _ in $(seq 1 36); do
          sleep 5
          if ssh_ok; then
            ok=1
            break
          fi
        done
        if [ "$ok" != 1 ]; then
          finish wake_failed "$sha" 1 0
        fi
      fi

      set +e
      safety_out=$(ssh "''${SSH_OPTS[@]}" "root@$HOST" /run/current-system/sw/bin/bash -s -- "$sha" <"$SAFETY")
      safety_rc=$?
      set -e
      safety_out="''${safety_out##*$'\n'}"
      safety_out="''${safety_out:-}"

      case "$safety_rc:$safety_out" in
        0:ok) ;;
        *:active) finish active "$sha" 1 0 ;;
        *:dirty) finish dirty "$sha" 1 0 ;;
        *:maintenance) finish maintenance "$sha" 1 0 ;;
        *)
          echo "ammars-pc-deploy: safety rc=$safety_rc out=$safety_out" >&2
          finish failure "$sha" 1 1
          ;;
      esac

      echo "ammars-pc-deploy: deploying $sha" >&2
      # Target-side TOCTOU guard marker (see hosts/desktop/configuration.nix):
      # root-owned, holds the exact SHA, exists only while this deploy runs
      # so both deploy-rs profile activations re-check lock/maintenance/repo
      # state right before mutating the system.
      marker=/run/ammars-pc-auto-deploy
      marker_clear() {
        ssh "''${SSH_OPTS[@]}" "root@$HOST" "rm -f $marker" >/dev/null 2>&1 || true
      }
      trap marker_clear EXIT
      # Root owns the marker, but standalone Home Manager runs the guard as
      # ammar and must read it. Write atomically with mode 0644.
      if ! ssh "''${SSH_OPTS[@]}" "root@$HOST" \
        "umask 022; printf '%s\n' $sha >$marker.tmp; chown root:root $marker.tmp; chmod 0644 $marker.tmp; mv -f $marker.tmp $marker"; then
        finish failure "$sha" 1 1
      fi
      if deploy --skip-checks --ssh-opts "''${SSH_OPTS[*]}" "git+$REPO?rev=$sha#ammars-pc"; then
        printf '%s\n' "$sha" >"$STATE/last-success"
        now >"$STATE/last-success-ts"
        rm -f "$STATE/pending" "$STATE/pending-since" "$STATE/last-ignored"
        if [ "$woke" = 1 ]; then
          finish woke_success "$sha" 0 0
        fi
        finish success "$sha" 0 0
      fi
      echo "ammars-pc-deploy: deploy-rs failed or rolled back" >&2
      finish failure "$sha" 1 1
    '';
  };
in
{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ../../_profiles/server/configuration.nix
    ../../../modules/nixos/networking.nix
    ./hermes.nix
  ];

  networking = {
    hostName = "aragorn";

    # Accept collie-lan-proxy and hermes-dashboard only from k3s nodes.
    # Do not open these ports broadly.
    firewall = {
      extraCommands = lib.concatMapStrings (
        src:
        lib.concatMapStrings
          (port: ''
            iptables -A nixos-fw -p tcp -s ${src} -d ${collieLanIp} --dport ${toString port} -j nixos-fw-accept
          '')
          [
            collieLanPort
            hermesLanPort
          ]
      ) collieSourceIps;
      extraStopCommands = lib.concatMapStrings (
        src:
        lib.concatMapStrings
          (port: ''
            iptables -D nixos-fw -p tcp -s ${src} -d ${collieLanIp} --dport ${toString port} -j nixos-fw-accept 2>/dev/null || true
          '')
          [
            collieLanPort
            hermesLanPort
          ]
      ) collieSourceIps;
    };
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # Plain tailnet client — not routing infrastructure
  modules = {
    # Finish before ammars-pc-deploy.timer at 04:30.
    comin.autoReboot = {
      enable = true;
      calendar = "*-*-* 04:00:00";
    };

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
      herdr-ntfy-env = {
        path = "secret/nixos/ntfy-publishers";
        field = "herdr-token"; # ignored because template is set
        template = ''
          HERDR_NTFY_SERVER=https://ntfy.dimensiondoor.xyz
          HERDR_NTFY_TOPIC=herdr
          HERDR_NTFY_TOKEN={{ with secret "secret/data/nixos/ntfy-publishers" }}{{ index .Data.data "herdr-token" }}{{ end }}
          HERDR_NTFY_NOTIFY_ON=done,blocked
          HERDR_NTFY_CLICK=https://collie.dimensiondoor.xyz
        '';
        owner = "ammar";
        group = "users";
        mode = "0400";
      };
      desktop-ntfy-curl-config = {
        path = "secret/nixos/ntfy-publishers";
        field = "desktop-deploy-token"; # ignored because template is set
        template = ''
          header = "Authorization: Bearer {{ with secret "secret/data/nixos/ntfy-publishers" }}{{ index .Data.data "desktop-deploy-token" }}{{ end }}"
        '';
        owner = "ammar";
        group = "users";
        mode = "0400";
      };
    };
  };

  # Keep the user manager alive for persistent agent sessions and user secrets.
  users.users.ammar.linger = true;

  # Dev/agent tooling on top of the minimal shared server home profile.
  # Function form so lib.hm (home-manager) is in scope for activation scripts.
  home-manager.users.ammar =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        ../../_profiles/dev/home.nix
        inputs.sops-nix.homeManagerModules.sops
        ../../../modules/home/dev/tea.nix
      ];

      sops = {
        age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
        defaultSopsFile = ../../../secrets/secrets.yaml;
        defaultSymlinkPath = "/run/user/1000/secrets";
        defaultSecretsMountPoint = "/run/user/1000/secrets.d";
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

        "herdr/plugins/config/cobanov.herdr-ntfysh/.env".source =
          config.lib.file.mkOutOfStoreSymlink "/run/secrets/herdr-ntfy-env";

        "herdr-mirror/hosts.toml".text = ''
          autostart = true
          close_remote_on_local_close = false
          always_control = false

          [hosts.desktop]
          target = "ammars-pc.lan"
          prefix = "desktop"
          remote_bin = "/home/ammar/.nix-profile/bin/herdr"

          [hosts.denethor]
          target = "denethor.lan"
          prefix = "denethor"
          remote_bin = "/etc/profiles/per-user/ammar/bin/herdr"
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

  programs.ssh.knownHosts."ammars-pc.lan" = {
    publicKey = desktopHostKey;
    extraHostNames = [ lanHosts.ammars-pc ];
  };

  services = {
    # Plan 2026-08-19 Phase 9/11: server profile already enables the exporter
    # with systemd+processes collectors (lists merge by concatenation); adding
    # textfile here also points it at the controller's metrics directory.
    prometheus.exporters.node = {
      enabledCollectors = [ "textfile" ];
      extraFlags = [ "--collector.textfile.directory=${metricsDir}" ];
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${stateDir} 0755 ammar users -"
      "d ${metricsDir} 0755 ammar users -"
    ];

    services.ammars-pc-deploy = {
      description = "Activity-aware deploy-rs for ammars-pc";
      after = [
        "network-online.target"
        "vault-agent-default.service"
      ];
      wants = [
        "network-online.target"
        "vault-agent-default.service"
      ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        User = "ammar";
        Group = "users";
        WorkingDirectory = stateDir;
        UMask = "0022";
        PrivateTmp = true;
        TimeoutStartSec = "2h";
        Environment = [
          "HOME=/home/ammar"
          "GIT_TERMINAL_PROMPT=0"
          "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
        ];
        ExecStart = lib.getExe ammarsPcDeploy;
      };
    };

    timers.ammars-pc-deploy = {
      description = "Daily 04:30 ammars-pc deploy";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:30:00";
        # No Persistent: a missed 04:30 (host down) must not fire a
        # desktop deploy midday while the machine may be in use.
      };
    };
  };
}
