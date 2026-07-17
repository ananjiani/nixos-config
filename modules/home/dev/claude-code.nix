{
  lib,
  pkgs,
  ...
}:

let
  # Community fix for prompt-cache + cost regressions in Claude Code
  # (cnighswonger/claude-code-cache-fix, v4.2.1). Native Bun claude-code
  # ignores NODE_OPTIONS, so we run the package's reverse proxy
  # (proxy/server.mjs) as a user systemd service on 127.0.0.1:9801 and
  # point the default claude wrapper at it via ANTHROPIC_BASE_URL.
  # claude-kimi/claude-glm set their own base URL and bypass the proxy.
  # Runtime deps (hpagent, proper-lockfile) come from buildNpmPackage.
  # Upstream npm tarball has no package-lock.json — inject a generated one.
  claudeCacheFix =
    let
      version = "4.2.1";
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/claude-code-cache-fix/-/claude-code-cache-fix-${version}.tgz";
        hash = "sha256-wzqxFyblnOqlpVDstYmebq9gRAD0bd0lN4Lfz4zm17o=";
      };
      # Generated via `npm install --package-lock-only --ignore-scripts` against v4.2.1.
      packageLock = pkgs.writeText "package-lock.json" ''
        {
          "name": "claude-code-cache-fix",
          "version": "4.2.1",
          "lockfileVersion": 3,
          "requires": true,
          "packages": {
            "": {
              "name": "claude-code-cache-fix",
              "version": "4.2.1",
              "hasInstallScript": true,
              "license": "MIT",
              "dependencies": {
                "hpagent": "^1.2.0",
                "proper-lockfile": "^4.1.2"
              },
              "bin": {
                "cache-fix-proxy": "bin/claude-via-proxy.mjs"
              },
              "engines": {
                "node": ">=18"
              },
              "funding": {
                "type": "individual",
                "url": "https://buymeacoffee.com/vsits"
              },
              "peerDependenciesMeta": {
                "sharp": {
                  "optional": true
                }
              }
            },
            "node_modules/graceful-fs": {
              "version": "4.2.11",
              "resolved": "https://registry.npmjs.org/graceful-fs/-/graceful-fs-4.2.11.tgz",
              "integrity": "sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==",
              "license": "ISC"
            },
            "node_modules/hpagent": {
              "version": "1.2.0",
              "resolved": "https://registry.npmjs.org/hpagent/-/hpagent-1.2.0.tgz",
              "integrity": "sha512-A91dYTeIB6NoXG+PxTQpCCDDnfHsW9kc06Lvpu1TEe9gnd6ZFeiBoRO9JvzEv6xK7EX97/dUE8g/vBMTqTS3CA==",
              "license": "MIT",
              "engines": {
                "node": ">=14"
              }
            },
            "node_modules/proper-lockfile": {
              "version": "4.1.2",
              "resolved": "https://registry.npmjs.org/proper-lockfile/-/proper-lockfile-4.1.2.tgz",
              "integrity": "sha512-TjNPblN4BwAWMXU8s9AEz4JmQxnD1NNL7bNOY/AKUzyamc379FWASUhc/K1pL2noVb+XmZKLL68cjzLsiOAMaA==",
              "license": "MIT",
              "dependencies": {
                "graceful-fs": "^4.2.4",
                "retry": "^0.12.0",
                "signal-exit": "^3.0.2"
              }
            },
            "node_modules/retry": {
              "version": "0.12.0",
              "resolved": "https://registry.npmjs.org/retry/-/retry-0.12.0.tgz",
              "integrity": "sha512-9LkiTwjUh6rT555DtE9rTX+BKByPfrMzEAtnlEtdEwr3Nkffwiihqe2bWADg+OQRjt9gl6ICdmB/ZFDCGAtSow==",
              "license": "MIT",
              "engines": {
                "node": ">= 4"
              }
            },
            "node_modules/signal-exit": {
              "version": "3.0.7",
              "resolved": "https://registry.npmjs.org/signal-exit/-/signal-exit-3.0.7.tgz",
              "integrity": "sha512-wnD2ZE+l+SPC/uoS0vXeE9L1+0wuaMqKlfz9AMUo38JsyLSBWSFcHR1Rri62LZc12vLr1gb3jl7iwQhgwpAbGQ==",
              "license": "ISC"
            }
          }
        }
      '';
      fixedSrc = pkgs.runCommand "claude-code-cache-fix-src-${version}" { } ''
        mkdir -p $out
        tar -xzf ${src} -C $out --strip-components=1
        cp ${packageLock} $out/package-lock.json
      '';
    in
    pkgs.buildNpmPackage {
      pname = "claude-code-cache-fix";
      inherit version;
      src = fixedSrc;
      npmDepsHash = "sha256-1VXn7N2jBCdiXLkJQCC3xA1Ofe7VND5InGyN1hRkO7s=";
      dontNpmBuild = true;
      npmInstallFlags = [ "--ignore-scripts" ];
    };

  cacheFixProxyServer = "${claudeCacheFix}/lib/node_modules/claude-code-cache-fix/proxy/server.mjs";

  # Wrap native pkgs.claude-code so default invocations hit the localhost
  # cache-fix reverse proxy. Only set ANTHROPIC_BASE_URL when unset so
  # claude-kimi / claude-glm (and any caller that sets its own endpoint)
  # bypass the proxy. Restores `claude` binary name for
  # programs.claude-code.package and ~/.local/bin/claude.
  claudeCodeWithCacheFix =
    let
      upstreamBin = "${pkgs.claude-code}/bin/claude";
      wrapper = pkgs.writeShellScript "claude-with-cache-fix" ''
        set -eu
        export ANTHROPIC_BASE_URL="''${ANTHROPIC_BASE_URL:-http://127.0.0.1:9801}"
        export ENABLE_TOOL_SEARCH="''${ENABLE_TOOL_SEARCH:-true}"
        exec ${upstreamBin} "$@"
      '';
    in
    pkgs.runCommand "claude-code-cache-fixed" { } ''
      mkdir -p $out/bin
      ln -s ${wrapper} $out/bin/claude
    '';

  # Shim that reads the Tavily API key from vault-agent's runtime secret
  # at exec time, then execs the real MCP server. Keeps the secret out of
  # the nix store and out of `ps` argv. Mirrors the claude-kimi/claude-glm
  # /run/secrets/... pattern.
  #
  # Tavily (via Cloudflare) rate-limits / blocks Mullvad exit IPs, so when
  # the setuid mullvad-exclude wrapper is available the MCP server is
  # launched in the `mullvad-exclusions` cgroup to bypass the VPN and use
  # the real WAN connection. Same cgroup trick already used for tailscaled
  # on ammars-pc and framework13 (see modules/nixos/tailscale.nix). Falls
  # back to direct exec on hosts without the wrapper so this stays host-
  # agnostic.
  tavilyMcpShim = pkgs.writeShellScript "tavily-mcp-shim" ''
    set -eu
    key_file=/run/secrets/tavily_api_key
    if [ ! -r "$key_file" ]; then
      echo "tavily-mcp-shim: $key_file not readable — is vault-agent configured for this host?" >&2
      exit 1
    fi
    export TAVILY_API_KEY="$(cat "$key_file")"
    mullvad_exclude=/run/wrappers/bin/mullvad-exclude
    if [ -x "$mullvad_exclude" ]; then
      exec "$mullvad_exclude" ${pkgs.nodejs}/bin/npx -y tavily-mcp@latest
    else
      exec ${pkgs.nodejs}/bin/npx -y tavily-mcp@latest
    fi
  '';

  # MCP config templates. Both use `__ZAI_KEY__` as a sentinel for the
  # z.ai Bearer token so the JSON can be built as a Nix attrset and
  # materialised to the store at eval time. At runtime the wrapper
  # does `sed "s|__ZAI_KEY__|$key|g"` into a mode-0600 temp file.

  # Shared between both wrappers — Tavily + self-hosted SearXNG.
  claudeAltMcpConfig = pkgs.writeText "claude-alt-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        tavily = {
          command = "${tavilyMcpShim}";
          args = [ ];
        };
        searxng = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [
            "-y"
            "mcp-searxng"
          ];
          env = {
            SEARXNG_URL = "https://searxng.lan";
            NODE_TLS_REJECT_UNAUTHORIZED = "0";
          };
        };
      };
    }
  );

  # Full config for claude-glm: Tavily + SearXNG + z.ai HTTP MCPs.
  claudeGlmMcpTemplate = pkgs.writeText "claude-glm-mcp-template.json" (
    builtins.toJSON {
      mcpServers = {
        tavily = {
          command = "${tavilyMcpShim}";
          args = [ ];
        };
        searxng = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [
            "-y"
            "mcp-searxng"
          ];
          env = {
            SEARXNG_URL = "https://searxng.lan";
            NODE_TLS_REJECT_UNAUTHORIZED = "0";
          };
        };
        web-reader = {
          type = "http";
          url = "https://api.z.ai/api/mcp/web_reader/mcp";
          headers = {
            Authorization = "Bearer __ZAI_KEY__";
          };
        };
        web-search-prime = {
          type = "http";
          url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
          headers = {
            Authorization = "Bearer __ZAI_KEY__";
          };
        };
        zread = {
          type = "http";
          url = "https://api.z.ai/api/mcp/zread/mcp";
          headers = {
            Authorization = "Bearer __ZAI_KEY__";
          };
        };
      };
    }
  );

  cfgBase = ./claude-code;
in
{
  # Home Manager supplies Claude Code plus version-controlled agents and commands.
  # Claude Code owns mutable ~/.claude/settings.json.
  programs.claude-code = {
    enable = true;
    package = claudeCodeWithCacheFix;

    agentsDir = "${cfgBase}/agents";
    commandsDir = "${cfgBase}/commands";
  };

  # Hook scripts + CLAUDE.md — individual home.file entries so
  # ~/.claude/hooks/ stays a writable directory (logs, __pycache__)
  # while the scripts themselves are immutable store paths.
  home.file = {
    ".claude/hooks/CLAUDE.md".source = "${cfgBase}/hooks/CLAUDE.md";
  }
  // (lib.mapAttrs'
    (
      name: _: lib.nameValuePair ".claude/hooks/src/${name}" { source = "${cfgBase}/hooks/src/${name}"; }
    )
    {
      "shared.py" = { };
      "pre_tool_use.py" = { };
      "post_tool_use.py" = { };
      "notification.py" = { };
      "stop.py" = { };
    }
  );

  # Local reverse proxy for cache-fix (default port 9801). Default claude
  # wrapper points here; alt-backend wrappers set their own base URL.
  systemd.user.services.cache-fix-proxy = {
    Unit = {
      Description = "Claude Code cache-fix reverse proxy";
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.nodejs}/bin/node ${cacheFixProxyServer}";
      Restart = "on-failure";
      RestartSec = "5";
      Environment = [
        "CACHE_FIX_PROXY_PORT=9801"
        "CACHE_FIX_PROXY_BIND=127.0.0.1"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home = {
    sessionPath = [ "$HOME/.local/bin" ];

    activation = {

      # Create stable binary path
      claudeStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        rm -f $HOME/.local/bin/claude
        ln -s ${claudeCodeWithCacheFix}/bin/claude $HOME/.local/bin/claude
      '';

      # Preserve config during switches
      preserveClaudeConfig = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
      '';

      restoreClaudeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
      '';
    };
  };

  programs.fish.functions = {
    # Wrapper that routes Claude Code directly to Moonshot's Kimi Code
    # product (api.kimi.com/coding), NOT their general API at
    # api.moonshot.ai. Kimi Code is a separate coding-specialised
    # service; its Anthropic-compatible endpoint serves a stable
    # `kimi-for-coding` model id that tracks the latest Kimi Code
    # model — currently K2.6 Code Preview (rolled out 2026-04-13).
    #
    # Previously routed through the self-hosted Bifrost gateway +
    # cliproxy (2026-04-10 → 2026-04-19). Dropped because Bifrost's
    # Messages→Responses-API translation plus the cliproxy middleman
    # proved unreliable in practice.
    #
    # Auth: Kimi Code `sk-kimi-*` keys are x-api-key style, so we use
    # ANTHROPIC_API_KEY (NOT ANTHROPIC_AUTH_TOKEN / Bearer, which is
    # what z.ai uses for claude-glm). API_TIMEOUT_MS is bumped because
    # K2.6 produces deeper reasoning traces and longer agent plans.
    #
    # WebSearch is deny-listed and replaced with a Tavily + SearXNG MCP
    # bundle because Kimi Code doesn't implement Anthropic's server-side
    # web_search_20250305 tool. ENABLE_TOOL_SEARCH=false disables the
    # ToolSearch beta for the same reason (same situation as claude-glm).
    #
    # Usage: claude-kimi [any claude args]
    claude-kimi = ''
      set -l key_file /run/secrets/kimi_code_api_key
      if not test -r $key_file
        echo "claude-kimi: $key_file not readable — is vault-agent configured for this host?" >&2
        return 1
      end
      env \
        ANTHROPIC_BASE_URL=https://api.kimi.com/coding \
        ANTHROPIC_API_KEY=(cat $key_file) \
        ANTHROPIC_DEFAULT_SONNET_MODEL=kimi-for-coding \
        ANTHROPIC_DEFAULT_OPUS_MODEL=kimi-for-coding \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=kimi-for-coding \
        API_TIMEOUT_MS=3000000 \
        ENABLE_TOOL_SEARCH=false \
        claude \
          --mcp-config ${claudeAltMcpConfig} \
          --disallowedTools WebSearch \
          $argv
    '';

    # Wrapper that routes Claude Code directly to z.ai's Anthropic-
    # compatible endpoint using GLM-5.1. Bypasses Bifrost because
    # Bifrost's /anthropic/v1/messages translates to the OpenAI
    # Responses API, which z.ai doesn't implement (see claude-kimi
    # comment above for the full story).
    #
    # z.ai requires Bearer auth, so we use ANTHROPIC_AUTH_TOKEN (sent
    # as Authorization: Bearer …), NOT ANTHROPIC_API_KEY (x-api-key).
    # API_TIMEOUT_MS is bumped per z.ai docs because GLM-5.1 is tuned
    # for long-horizon agentic runs.
    #
    # WebSearch is deny-listed and replaced with a Tavily MCP (same
    # reasoning as claude-kimi above). ENABLE_TOOL_SEARCH=false because
    # z.ai doesn't implement Anthropic's ToolSearch beta either.
    #
    # Also wires three z.ai remote HTTP MCPs (all Bearer-auth'd with the
    # same zai_api_key):
    #   - web-reader: fetch/parse arbitrary URLs, complements Tavily's
    #     search-only API. docs.z.ai/devpack/mcp/reader-mcp-server
    #   - web-search-prime: z.ai native web search, returns titles/URLs/
    #     summaries. docs.z.ai/devpack/mcp/search-mcp-server
    #   - zread: read docs/code from GitHub-style repos via zread.ai.
    #     docs.z.ai/devpack/mcp/zread-mcp-server
    # The MCP config is a Nix-generated JSON template (claudeGlmMcpTemplate)
    # with a __ZAI_KEY__ sentinel. At runtime the wrapper sed-replaces the
    # sentinel into a mode-0600 temp file so the Bearer token never hits
    # the nix store.
    #
    # Usage: claude-glm [any claude args]
    claude-glm = ''
      set -l key_file /run/secrets/zai_api_key
      if not test -r $key_file
        echo "claude-glm: $key_file not readable — is vault-agent configured for this host?" >&2
        return 1
      end
      set -l zai_key (cat $key_file)
      set -l mcp_config (mktemp -t claude-glm-mcp.XXXXXX.json)
      chmod 600 $mcp_config
      sed "s|__ZAI_KEY__|$zai_key|g" ${claudeGlmMcpTemplate} > $mcp_config
      env \
        ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
        ANTHROPIC_AUTH_TOKEN=$zai_key \
        ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.1 \
        ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.5-air \
        API_TIMEOUT_MS=3000000 \
        ENABLE_TOOL_SEARCH=false \
        claude \
          --mcp-config $mcp_config \
          --disallowedTools WebSearch \
          $argv
      set -l rc $status
      rm -f $mcp_config
      return $rc
    '';
  };
}
