{ config, pkgs, ... }:

let
  # Absolute path to the user-editable pi resources dir in the working
  # tree. Hardcoded to ~/.dotfiles — the canonical checkout location this
  # repo assumes elsewhere (e.g. vault-agent bootstrap). Each subdirectory
  # below is out-of-store-symlinked so pi can hot-reload/write in-session
  # and the changes land directly in the git working tree.
  piUserDir = "${config.home.homeDirectory}/.dotfiles/modules/home/dev/pi-coding-agent";

  # Pi ships built-in providers `kimi-coding` (api.kimi.com/coding) and
  # `zai` (api.z.ai/api/anthropic) — see pi-mono packages/ai/src/models.generated.ts.
  # We only need to supply apiKeys; the base URLs, model IDs, and auth
  # flavors are already correct.
  #
  # IMPORTANT: custom provider names that COLLIDE with or don't match
  # pi's built-in registry fall back to fuzzy model matching (e.g.
  # `--provider kimi` matched huggingface's "moonshotai/Kimi-K2.5" on
  # first try, yielding a 401 from HF's token auth). Always use exact
  # built-in provider ids to override, or use fully novel names.
  #
  # Reuses /run/secrets/* already rendered by vault-agent for claude-kimi
  # and claude-glm. Pi's "!cmd" apiKey form runs the cat at invocation
  # time, stripping trailing whitespace — key stays out of the env table
  # and rotates with vault-agent's lease.
  # Web access via two small bash scripts on PATH. Mario's pitch is
  # "CLI tools with READMEs" instead of MCP servers — pi's bash tool
  # discovers these when asked to search/fetch, no tokens spent
  # registering them up-front. Tool choices follow the pi ecosystem
  # (pi-amplike, pi-skills/brave-search, pi-super-curl):
  #
  # - `web-search <query>`: self-hosted SearXNG at searxng.lan
  # - `web-fetch <url>`:    Jina Reader (r.jina.ai) — free, Readability-
  #                         based extraction, handles JS-rendered pages,
  #                         de-facto web-fetch standard in the pi
  #                         community. Strictly better than pandoc for
  #                         agent use (article extraction vs blind
  #                         HTML→markdown).
  #
  # Tavily and pandoc were considered and dropped — Tavily isn't used
  # anywhere in the pi ecosystem (it's a Claude Code pattern), and
  # pandoc converts HTML-as-markup instead of extracting article
  # bodies. If higher-quality search becomes load-bearing, add a
  # `web-search-brave` wrapping Mario's pi-skills/brave-search.

  webSearch = pkgs.writeShellApplication {
    name = "web-search";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      # Usage: web-search <query...>
      #
      # Queries the self-hosted SearXNG at searxng.lan and prints the
      # top 10 results as markdown-ish plain text (title, URL, snippet).
      # For reading a specific URL use `web-fetch`.
      if [ $# -eq 0 ]; then
        echo "usage: web-search <query...>" >&2
        exit 1
      fi
      query=$(printf '%s' "$*" | jq -sRr @uri)
      # -k: searxng.lan has a self-signed cert (same reason mcp-searxng
      # sets NODE_TLS_REJECT_UNAUTHORIZED=0 in claude-code.nix).
      curl -fsSLk --max-time 15 \
        "https://searxng.lan/search?q=''${query}&format=json&safesearch=0" \
        | jq -r '.results[:10] | .[] | "## \(.title)\n\(.url)\n\(.content // "")\n"'
    '';
  };

  webFetch = pkgs.writeShellApplication {
    name = "web-fetch";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      # Usage: web-fetch <url>
      #
      # Fetches <url> via Jina Reader, which returns clean markdown
      # (Readability-based extraction, JS-rendered pages supported, ads
      # and navigation removed, links preserved inline). Free tier has
      # rate limits but no API key required. Set JINA_API_KEY in the
      # environment if you hit limits — forwarded as Bearer auth.
      if [ $# -ne 1 ]; then
        echo "usage: web-fetch <url>" >&2
        exit 1
      fi
      if [ -n "''${JINA_API_KEY:-}" ]; then
        exec curl -fsSL --max-time 30 \
          -H "Authorization: Bearer $JINA_API_KEY" \
          "https://r.jina.ai/$1"
      else
        exec curl -fsSL --max-time 30 "https://r.jina.ai/$1"
      fi
    '';
  };

  piModels = pkgs.writeText "pi-models.json" (
    builtins.toJSON {
      providers = {
        # Use pi's built-in kimi-coding + zai providers (see pi-mono
        # packages/ai/src/models.generated.ts) — correct baseUrls, model
        # ids, and API protocols already wired. We only supply apiKeys.
        #
        # NOTE: kimi-coding uses anthropic-messages at api.kimi.com/coding
        # (same as claude-kimi). zai uses openai-completions at
        # api.z.ai/api/coding/paas/v4 — DIFFERENT from claude-glm, which
        # speaks anthropic-messages at api.z.ai/api/anthropic. Pi doesn't
        # need Anthropic-protocol-everywhere like Claude Code does, so
        # the Coding-PaaS endpoint is the right default.
        #
        # `baseUrl` redeclaration is required: pi 0.68.1's model-registry
        # rejects override-only configs that don't declare one of baseUrl/
        # compat/modelOverrides/models. apiKey-only configs trigger
        # "Failed to load models.json: Provider X: must specify …",
        # visible only via `pi --list-models`; at request time pi just
        # reports "No API key found". Redeclaring the built-in baseUrl
        # here is a harmless no-op that unblocks the apiKey override.
        kimi-coding = {
          apiKey = "!cat /run/secrets/kimi_code_api_key";
          baseUrl = "https://api.kimi.com/coding";
        };

        # z.ai's Coding-PaaS endpoint (openai-completions protocol).
        # Different from claude-glm's api.z.ai/api/anthropic — pi doesn't
        # need Anthropic-protocol-everywhere like Claude Code does, so the
        # native PaaS endpoint is the right default.
        zai = {
          apiKey = "!cat /run/secrets/zai_api_key";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
        };
      };
    }
  );
in
{
  # numtide/llm-agents.nix's default overlay namespaces everything under
  # pkgs.llm-agents.* (not top-level pkgs.pi).
  #
  # models.json is a /nix/store symlink (immutable — secrets-config).
  # extensions/, prompts/, skills/, settings.json are OUT-OF-STORE
  # symlinks into the dotfiles working tree so pi's `/reload`, `/settings`,
  # `/scoped-models` and `pi config` interactive edits land directly in
  # git. Changing the SHAPE (adding a folder, bumping the package) still
  # needs `nh home switch`; iterating on individual files does not.
  #
  # settings.json holds defaults pi can mutate via /settings, /scoped-
  # models (Ctrl+S), pi config, and `pi install`. We seed it with our
  # canonical defaults (default provider/model/thinking level + the
  # scoped-model cycle list for Ctrl+P) and let pi accumulate any
  # interactive changes back into git.
  #
  # pi also writes ~/.pi/agent/{auth.json,sessions/} at runtime — NOT
  # symlinked here, pi manages them as mutable runtime state.
  home = {
    packages = [
      pkgs.llm-agents.pi
      webSearch
      webFetch
    ];
    sessionVariables.PI_CACHE_RETENTION = "long";
    file = {
      ".pi/agent/models.json".source = piModels;
      ".pi/agent/extensions".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/extensions";
      ".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/prompts";
      ".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/skills";
      ".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/settings.json";
    };
  };
}
