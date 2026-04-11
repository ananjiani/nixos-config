{
  lib,
  pkgs,
  ...
}:

let
  # Shim that reads the Tavily API key from vault-agent's runtime secret
  # at exec time, then execs the real MCP server. Keeps the secret out of
  # the nix store and out of `ps` argv. Mirrors the claude-kimi/claude-glm
  # /run/secrets/... pattern.
  tavilyMcpShim = pkgs.writeShellScript "tavily-mcp-shim" ''
    set -eu
    key_file=/run/secrets/tavily_api_key
    if [ ! -r "$key_file" ]; then
      echo "tavily-mcp-shim: $key_file not readable — is vault-agent configured for this host?" >&2
      exit 1
    fi
    export TAVILY_API_KEY="$(cat "$key_file")"
    exec ${pkgs.nodejs}/bin/npx -y tavily-mcp@latest
  '';

  # Static MCP config consumed by claude-kimi and claude-glm via
  # `--mcp-config`. Provides an external web-search tool since neither
  # z.ai nor Bifrost/cliproxy can proxy Anthropic's server-side
  # WebSearch tool (web_search_20250305). Loaded additively alongside
  # any other MCPs the user has configured.
  claudeAltMcpConfig = pkgs.writeText "claude-alt-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        tavily = {
          command = "${tavilyMcpShim}";
          args = [ ];
        };
      };
    }
  );
in
{
  home = {
    packages = with pkgs; [
      claude-code
    ];

    sessionPath = [ "$HOME/.local/bin" ];

    activation = {
      # Create stable binary path
      claudeStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        rm -f $HOME/.local/bin/claude
        ln -s ${pkgs.claude-code}/bin/claude $HOME/.local/bin/claude
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
    # Usage: claude-glm [any claude args]
    claude-glm = ''
      set -l key_file /run/secrets/zai_api_key
      if not test -r $key_file
        echo "claude-glm: $key_file not readable — is vault-agent configured for this host?" >&2
        return 1
      end
      env \
        ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
        ANTHROPIC_AUTH_TOKEN=(cat $key_file) \
        ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.1 \
        ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1 \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-4.5-air \
        API_TIMEOUT_MS=3000000 \
        ENABLE_TOOL_SEARCH=false \
        claude \
          --mcp-config ${claudeAltMcpConfig} \
          --disallowedTools WebSearch \
          $argv
    '';
  };
}
