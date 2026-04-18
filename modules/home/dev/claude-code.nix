{
  lib,
  pkgs,
  ...
}:

let
  # Community fix for the post-v2.1.68 prompt-cache regression
  # (cnighswonger/claude-code-cache-fix). A Node.js preload that hooks
  # globalThis.fetch and relocates attachment blocks back to messages[0]
  # (plus tool sorting + fingerprint stabilization). URL-guarded to
  # /v1/messages requests with valid Anthropic body shape — safe no-op
  # everywhere else (MCPs, claude-kimi/claude-glm alt-backend wrappers).
  #
  # IMPORTANT: only works against the Node runtime variant of claude-code
  # (pkgs.claude-code-node, binary `claude-node`). The native bundled
  # binary ignores NODE_OPTIONS entirely. See claudeCodeWithCacheFix below.
  claudeCacheFix =
    let
      version = "2.0.3";
    in
    pkgs.runCommand "claude-code-cache-fix-${version}"
      {
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/claude-code-cache-fix/-/claude-code-cache-fix-${version}.tgz";
          hash = "sha256-kjbbqiS9S0PReGitO/T8at9DrGJ5AJ1C1mm8zmPKejk=";
        };
      }
      ''
        mkdir -p $out/lib/node_modules/claude-code-cache-fix
        tar -xzf $src -C $out/lib/node_modules/claude-code-cache-fix --strip-components=1
      '';

  # Wrap claude-code-node so every invocation gets the cache-fix preload.
  # Same shape as tavilyMcpShim — small shell script that sets env then
  # execs the upstream binary. We restore the `claude` binary name so
  # programs.claude-code.package and the ~/.local/bin/claude symlink
  # work unchanged downstream.
  claudeCodeWithCacheFix =
    let
      upstreamBin = "${pkgs.claude-code-node}/bin/claude-node";
      preload = "${claudeCacheFix}/lib/node_modules/claude-code-cache-fix/preload.mjs";
      wrapper = pkgs.writeShellScript "claude-with-cache-fix" ''
        set -eu
        # Append rather than overwrite — preserve any user-supplied NODE_OPTIONS.
        export NODE_OPTIONS="''${NODE_OPTIONS:-} --import file://${preload}"
        # Silence "Cannot open directory .../openssl-*/etc/ssl/certs" warning.
        # claude-code-node bundles its own openssl whose default cert lookup
        # paths point into a nix-store path that doesn't exist (openssl's
        # `etc` output isn't propagated). The warning is specifically about a
        # directory, so SSL_CERT_DIR is the one that suppresses it.
        # SSL_CERT_FILE is set as well for any code path that reads a single
        # bundle. NIX_SSL_CERT_FILE is the NixOS convention for the bundle.
        export SSL_CERT_DIR="''${SSL_CERT_DIR:-/etc/ssl/certs}"
        export SSL_CERT_FILE="''${SSL_CERT_FILE:-''${NIX_SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}}"
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
  # Declarative Claude Code configuration via the official home-manager module.
  # Manages settings.json, agents, and commands as immutable nix store paths.
  programs.claude-code = {
    enable = true;
    package = claudeCodeWithCacheFix;

    settings = {
      attribution = {
        commit = "";
        pr = "";
      };

      permissions = {
        allow = [
          "Bash(mkdir:*)"
          "Bash(uv:*)"
          "Bash(mv:*)"
          "Bash(npm:*)"
          "Bash(ls:*)"
          "Bash(cp:*)"
          "Bash(chmod:*)"
          "Bash(touch:*)"
          "Bash(rg:*)"
          "Bash(fd:*)"
          "Bash(jq:*)"
          "Bash(ls:*)"
          "Bash(cat:*)"
          "Bash(echo:*)"
          "Bash(cd:*)"
        ];
        deny = [
          "Bash(sops -d:*)"
          "Bash(sops --decrypt:*)"
        ];
      };

      hooks = {
        PreToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/src/pre_tool_use.py";
              }
            ];
          }
        ];
        PostToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/src/post_tool_use.py";
              }
            ];
          }
        ];
        Notification = [
          {
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/src/notification.py";
              }
            ];
          }
        ];
      };

      statusLine = {
        type = "command";
        command = ''input=$(cat); current_dir=$(echo "$input" | jq -r '.workspace.current_dir'); model=$(echo "$input" | jq -r '.model.display_name'); style=$(echo "$input" | jq -r '.output_style.name'); git_info=""; if [ -d "$current_dir/.git" ]; then cd "$current_dir" && branch=$(git branch --show-current 2>/dev/null) && git_info=" [$branch]"; fi; printf "\033[2m%s in %s%s | %s\033[0m" "$model" "$(basename "$current_dir")" "$git_info" "$style"'';
      };

      enabledPlugins = {
        "pyright-lsp@claude-plugins-official" = true;
      };

      effortLevel = "xhigh";

      skipDangerousModePermissionPrompt = true;

      mcpServers = {
        persona = {
          type = "http";
          url = "https://mcp.persona.lan/mcp";
        };
      };
    };

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

  home = {
    sessionPath = [ "$HOME/.local/bin" ];
    sessionVariables.ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-7";

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
    # Wrapper that routes Claude Code through the self-hosted Bifrost
    # LLM gateway, targeting cliproxy's Kimi-for-coding model.
    #
    # Per Kimi Code docs: ENABLE_TOOL_SEARCH=false for Claude Code compatibility.
    # Smoke-tested 2026-04-10: zai and deepseek 404 via Bifrost's Anthropic
    # endpoint because Bifrost translates Messages API → OpenAI Responses API
    # (/v1/responses), which those upstreams don't implement. cliproxy is a
    # flexible passthrough so it works.
    #
    # WebSearch is deny-listed and replaced with a Tavily MCP because
    # Anthropic's server-side web_search_20250305 tool can't be proxied
    # through Bifrost/cliproxy — vanilla Claude Code routes it to
    # api.anthropic.com directly, but the upstream here doesn't implement it.
    #
    # Usage: claude-kimi [any claude args]
    claude-kimi = ''
      set -l vk_file /run/secrets/bifrost_api_key
      if not test -r $vk_file
        echo "claude-kimi: $vk_file not readable — is vault-agent configured for this host?" >&2
        return 1
      end
      env \
        ANTHROPIC_BASE_URL=https://bifrost.lan/anthropic \
        ANTHROPIC_API_KEY=(cat $vk_file) \
        ANTHROPIC_MODEL=cliproxy/kimi-for-coding \
        ANTHROPIC_SMALL_FAST_MODEL=cliproxy/kimi-for-coding \
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
