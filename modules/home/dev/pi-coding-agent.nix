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

  # Two separate tools, model decides which to use. Local extraction is
  # private (URL stays on-box, only the curl request leaves, routed
  # through Mullvad) but can't handle JS-rendered SPAs or auth-walled
  # pages. Jina handles those but sees every URL you fetch. Splitting
  # them surfaces the privacy/capability tradeoff explicitly to the
  # agent — Mario's "small CLIs with READMEs" pattern. The agent reads
  # --help, picks the right tool, falls back when needed.

  webFetch = pkgs.writeShellApplication {
    name = "web-fetch";
    runtimeInputs = [
      pkgs.curl
      pkgs.nodePackages.readability-cli
      pkgs.python3Packages.html2text
    ];
    text = ''
      # Usage: web-fetch <url>
      #
      # Local Readability-based extraction. curl -> Mozilla Readability
      # (same algorithm Firefox Reader Mode uses, in pi-skills/brave-
      # search style) -> html2text (markdown output). URL stays on-box;
      # only the curl request itself leaves, routed through whatever VPN
      # is active.
      #
      # Trivial output (<500 chars) usually means a JS-rendered SPA, an
      # auth-walled page, or a soft-404 — try `web-fetch-jina <url>`
      # which renders JS server-side and is more lenient about extraction.
      # Trade-off: every URL you fetch through web-fetch-jina is logged
      # by Jina; web-fetch keeps URLs private.
      if [ $# -ne 1 ]; then
        echo "usage: web-fetch <url>" >&2
        echo "  Local Readability extraction. URL stays on-box." >&2
        echo "  For JS-rendered or auth-walled pages, use web-fetch-jina." >&2
        exit 1
      fi
      url=$1
      tmpfile=$(mktemp --suffix=.html)
      trap 'rm -f "$tmpfile"' EXIT

      curl -fsSL --max-time 30 -A "Mozilla/5.0 pi-coding-agent" "$url" -o "$tmpfile"
      output=$(readable "$tmpfile" --base "$url" --quiet --low-confidence=force 2>/dev/null \
        | html2text --body-width=0 2>/dev/null || true)
      printf '%s\n' "$output"

      # Hint stderr so the model learns about the alternative when the
      # extraction looks empty. Agent reads stderr alongside stdout.
      if [ "''${#output}" -lt 500 ]; then
        echo "[web-fetch] only ''${#output} chars extracted — try web-fetch-jina for JS-rendered or auth-walled pages" >&2
      fi
    '';
  };

  webFetchJina = pkgs.writeShellApplication {
    name = "web-fetch-jina";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      # Usage: web-fetch-jina <url>
      #
      # Jina Reader (r.jina.ai). Server-side Readability extraction with
      # JS rendering — handles SPAs, dynamically-generated content, and
      # any page where local extraction (`web-fetch`) returns trivial
      # output. Free tier rate-limited; set JINA_API_KEY for more.
      #
      # Privacy note: every URL fetched here is sent to Jina's servers.
      # For private fetches, prefer `web-fetch` (local extraction).
      if [ $# -ne 1 ]; then
        echo "usage: web-fetch-jina <url>" >&2
        echo "  Jina Reader (handles JS pages). URL is logged by Jina." >&2
        echo "  For private fetches, use web-fetch (local extraction)." >&2
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
  # Generate a Pi TUI theme from Stylix's base16 palette so the
  # coding agent's colors stay in sync with the rest of the desktop.
  # Uses config.lib.stylix.colors (base00–base0F) to build all 51
  # required Pi theme tokens + an HTML export section.
  piTheme =
    let
      c = config.lib.stylix.colors;
    in
    pkgs.writeText "gruvbox-material.json" (
      builtins.toJSON {
        "$schema" =
          "https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
        name = "gruvbox-material";
        vars = {
          bg = "#${c.base00}";
          bg1 = "#${c.base01}";
          bg2 = "#${c.base02}";
          dimFg = "#${c.base03}";
          light1 = "#${c.base04}";
          fg = "#${c.base05}";
          light2 = "#${c.base06}";
          bright = "#${c.base07}";
          red = "#${c.base08}";
          orange = "#${c.base09}";
          yellow = "#${c.base0A}";
          green = "#${c.base0B}";
          aqua = "#${c.base0C}";
          blue = "#${c.base0D}";
          purple = "#${c.base0E}";
          brown = "#${c.base0F}";
        };
        colors = {
          # Core UI
          accent = "orange";
          border = "blue";
          borderAccent = "aqua";
          borderMuted = "bg2";
          success = "green";
          error = "red";
          warning = "yellow";
          muted = "dimFg";
          dim = "bg2";
          text = "";
          thinkingText = "dimFg";

          # Backgrounds & content
          selectedBg = "bg2";
          userMessageBg = "bg1";
          userMessageText = "";
          customMessageBg = "bg1";
          customMessageText = "";
          customMessageLabel = "purple";
          toolPendingBg = "bg1";
          toolSuccessBg = "bg1";
          toolErrorBg = "bg1";
          toolTitle = "orange";
          toolOutput = "dimFg";

          # Markdown
          mdHeading = "yellow";
          mdLink = "blue";
          mdLinkUrl = "dimFg";
          mdCode = "aqua";
          mdCodeBlock = "light1";
          mdCodeBlockBorder = "dimFg";
          mdQuote = "dimFg";
          mdQuoteBorder = "dimFg";
          mdHr = "dimFg";
          mdListBullet = "orange";

          # Tool diffs
          toolDiffAdded = "green";
          toolDiffRemoved = "red";
          toolDiffContext = "dimFg";

          # Syntax highlighting
          syntaxComment = "dimFg";
          syntaxKeyword = "orange";
          syntaxFunction = "yellow";
          syntaxVariable = "light1";
          syntaxString = "green";
          syntaxNumber = "purple";
          syntaxType = "aqua";
          syntaxOperator = "light1";
          syntaxPunctuation = "light1";

          # Thinking level borders
          thinkingOff = "bg2";
          thinkingMinimal = "dimFg";
          thinkingLow = "blue";
          thinkingMedium = "aqua";
          thinkingHigh = "purple";
          thinkingXhigh = "red";

          # Bash mode
          bashMode = "green";
        };
        export = {
          pageBg = "#${c.base00}";
          cardBg = "#${c.base01}";
          infoBg = "#${c.base02}";
        };
      }
    );

  # Minimal bubblewrap sandbox for pi. Passes through the full host
  # environment (PATH, devshell vars, direnv) so the agent can use
  # kubectl, tofu, deploy, etc. when needed. The isolation is purely
  # filesystem-level:
  #
  #   - $HOME is an ephemeral tmpfs (agent can't read ~/.ssh, browser
  #     profiles, dotfiles outside the explicitly bind-mounted paths)
  #   - ~/.pi/agent is bind-mounted back (sessions, auth, config tree)
  #   - /nix/store is read-only (agent can't corrupt the store)
  #   - CWD is bind-mounted read-write
  #   - /run/secrets is read-only (for pi's "!cat /run/secrets/..."
  #     apiKey pattern)
  #   - /tmp is shared (pi's extensions/tools need scratch space)
  #
  # This preserves the devshell workflow — the agent inherits whatever
  # `nix develop` or `direnv` sets up — while preventing it from
  # reading private files outside the project and pi's own state.
  # writeShellScriptBin (not writeShellApplication!) — we explicitly
  # want the host PATH to flow through so the devshell's tools (npm,
  # kubectl, tofu, etc.) are available inside the sandbox.
  # writeShellApplication would cage PATH to only runtimeInputs.
  pi-sandboxed = pkgs.writeShellScriptBin "pi" ''
    CWD=$(pwd)
    HOME_REAL="$HOME"

    exec ${pkgs.bubblewrap}/bin/bwrap \
      --ro-bind /nix/store /nix/store \
      --ro-bind /nix/var /nix/var \
      --ro-bind /etc /etc \
      --ro-bind /bin /bin \
      --ro-bind /usr /usr \
      $(test -d /run/secrets && echo "--ro-bind /run/secrets /run/secrets") \
      --ro-bind /run/systemd /run/systemd \
      --dev /dev \
      --proc /proc \
      --bind /tmp /tmp \
      --tmpfs "$HOME_REAL" \
      --bind "$HOME_REAL/.cache" "$HOME_REAL/.cache" \
      --bind "$HOME_REAL/.dotfiles" "$HOME_REAL/.dotfiles" \
      --bind "$HOME_REAL/.pi/agent" "$HOME_REAL/.pi/agent" \
      --bind "$HOME_REAL/.nix-profile" "$HOME_REAL/.nix-profile" \
      $(test -d "$HOME_REAL/.npm-global" && echo "--bind $HOME_REAL/.npm-global $HOME_REAL/.npm-global") \
      $(test -f "$HOME_REAL/.npmrc" && echo "--ro-bind $HOME_REAL/.npmrc $HOME_REAL/.npmrc") \
      $(test -d "$HOME_REAL/.npm" && echo "--bind $HOME_REAL/.npm $HOME_REAL/.npm") \
      $(test -d "$HOME_REAL/.local" && echo "--bind $HOME_REAL/.local $HOME_REAL/.local") \
      --bind "$CWD" "$CWD" \
      --chdir "$CWD" \
      --die-with-parent \
      --share-net \
      --setenv PATH "${pkgs.coreutils}/bin:$PATH" \
      -- ${pkgs.llm-agents.pi}/bin/pi "$@"
  '';

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
      pi-sandboxed
      # Unwrapped pi for when the sandbox causes issues.
      # Identical to pkgs.llm-agents.pi — no bubblewrap isolation.
      (pkgs.writeShellScriptBin "pi-unsafe" ''
        exec ${pkgs.llm-agents.pi}/bin/pi "$@"
      '')
      webSearch
      webFetch
      webFetchJina
    ];
    sessionVariables.PI_CACHE_RETENTION = "long";
    file = {
      ".pi/agent/models.json".source = piModels;
      ".pi/agent/extensions".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/extensions";
      ".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/prompts";
      ".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/skills";
      ".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/settings.json";
      ".pi/agent/themes/gruvbox-material.json".source = piTheme;
    };
  };
}
