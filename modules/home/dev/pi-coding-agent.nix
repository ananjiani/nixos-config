{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.piCodingAgent;

  # Absolute path to the user-editable pi resources dir in the working
  # tree. Hardcoded to ~/.dotfiles — the canonical checkout location this
  # repo assumes elsewhere (e.g. vault-agent bootstrap). Each subdirectory
  # below is out-of-store-symlinked so pi can hot-reload/write in-session
  # and the changes land directly in the git working tree.
  piUserDir = "${config.home.homeDirectory}/.dotfiles/modules/home/dev/pi-coding-agent";

  # Sources tracked by nvfetcher (run `nix run github:berberman/nvfetcher`
  # to bump). Mirrors modules/nixos/htpc.nix; depth differs (3 vs 2), so
  # the `../../` there would land at `modules/_sources/` here.
  sources = import ../../../_sources/generated.nix {
    inherit (pkgs)
      fetchurl
      fetchFromGitHub
      fetchgit
      dockerTools
      ;
  };

  # Parenthesis checker for agent-generated Emacs Lisp (kiyoka/agent-
  # lisp-paren-aid). Runs the .el through Emacs' re-indenter and reports
  # the exact line where parens are unbalanced — too many or too few.
  # LLMs get the indentation right but miscount closers; this catches
  # that class of bug the agent can't self-verify by counting. See
  # skills/elisp/SKILL.md for how pi is told to reach for it after
  # every .el edit. Go static binary, no autoPatchelf needed.
  agent-lisp-paren-aid = pkgs.stdenv.mkDerivation {
    pname = "agent-lisp-paren-aid";
    inherit (sources.agent-lisp-paren-aid) version src;
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      install -Dm555 $src $out/bin/agent-lisp-paren-aid
      runHook postInstall
    '';
  };

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

  # Endpoint is an option so portable/isolated hosts (e.g. Denethor) can
  # set null and keep searxng.lan out of the store path entirely.
  webSearch =
    if cfg.searxngUrl == null then
      pkgs.writeShellApplication {
        name = "web-search";
        text = ''
          # Usage: web-search <query...>
          #
          # SearXNG endpoint not configured on this host (piCodingAgent.searxngUrl = null).
          echo "web-search: not configured (piCodingAgent.searxngUrl is null)" >&2
          exit 1
        '';
      }
    else
      pkgs.writeShellApplication {
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
            "${cfg.searxngUrl}/search?q=''${query}&format=json&safesearch=0" \
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
      pkgs.readability-cli
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

      # Auto-append .rss to Reddit thread URLs. Reddit blocks all
      # unauthenticated HTML/JSON endpoints (403) regardless of IP —
      # Mullvad, residential, even Jina's servers are blocked. The
      # .rss endpoint is the only one that works without auth.
      # Resolve shortlink/share redirectors first: redd.it/<id> and
      # share.reddit.com/... 301 to www.reddit.com/comments/<id>, whose
      # canonical form has NO /r/<sub>/ segment. One HEAD-with--L captures
      # the final URL so the regex below handles it uniformly. Direct
      # reddit.com links (the common case) skip the extra hop.
      case "$url" in
        http://redd.it/* | https://redd.it/* | http*://share.reddit.com/*)
          resolved=$(curl -sIL -o /dev/null -w '%{url_effective}' \
            --max-time 15 -A "Mozilla/5.0 pi-coding-agent" "$url" 2>/dev/null || true)
          if [ -n "$resolved" ]; then url=$resolved; fi
          ;;
      esac
      # /r/<sub>/comments/ and bare /comments/ both accept .rss without auth.
      if [[ "$url" =~ ^https?://(www\.|old\.)?reddit\.com/(r/[^/]+/)?comments/ ]] && \
         [[ ! "$url" =~ \.rss$ ]]; then
        url=$(printf '%s' "$url" | sed 's|/*$||').rss
      fi

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

  # ─── Repo Ingest ───────────────────────────────────────────────────────────
  #
  # Packs any git repository (GitHub, GitLab, Codeberg, Gitea, self-hosted)
  # into a single AI-friendly plain-text dump. Wraps repomix (nixpkgs).
  #
  # Usage:
  #   repo-ingest <git-url|local-path> [--include <glob>] [--compress]
  #
  # Examples:
  #   repo-ingest https://github.com/nixos/nixpkgs --include "pkgs/top-level/*.nix"
  #   repo-ingest https://codeberg.org/forgejo/forgejo --compress
  #   repo-ingest ./my-project --include "src/**/*.ts"

  repoIngest = pkgs.writeShellApplication {
    name = "repo-ingest";
    runtimeInputs = [
      pkgs.repomix
      pkgs.git
    ];
    text = ''
      set -euo pipefail

      usage() {
        echo "usage: repo-ingest <git-url|local-path> [--include <glob>] [--compress]" >&2
        echo "  Pack a repository into a single AI-friendly plain-text dump." >&2
        echo "  Works with GitHub, GitLab, Codeberg, Gitea, and any git host." >&2
        exit 1
      }

      [ $# -lt 1 ] && usage

      target=$1
      shift

      include=""
      compress=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --include) include="$2"; shift 2 ;;
          --compress) compress="1"; shift ;;
          *) echo "unknown option: $1" >&2; usage ;;
        esac
      done

      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      # If it looks like a URL, shallow-clone it; otherwise use local path
      if [[ "$target" =~ ^(https?://|git@) ]]; then
        echo "[repo-ingest] cloning $target ..." >&2
        git clone --depth 1 "$target" "$tmpdir/repo" >&2
        cd "$tmpdir/repo"
      else
        cd "$target"
      fi

      args=(--style plain --output "$tmpdir/output.txt")
      [ -n "$include" ] && args+=(--include "$include")
      [ -n "$compress" ] && args+=(--compress)

      repomix "''${args[@]}" >&2
      cat "$tmpdir/output.txt"
    '';
  };

  # ─── Repo Browse ───────────────────────────────────────────────────────────
  #
  # Targeted exploration of any git repository without downloading full
  # history. Shallow-clones with --depth 1 and caches in /tmp for the
  # session. Works with any git host.
  #
  # Usage:
  #   repo-browse ls   <git-url> [path]      # list directory
  #   repo-browse cat  <git-url> <path>      # read a file
  #   repo-browse grep <git-url> <pattern>   # grep file contents
  #   repo-browse tree <git-url> [path]      # show directory tree

  repoBrowse = pkgs.writeShellApplication {
    name = "repo-browse";
    runtimeInputs = [
      pkgs.git
      pkgs.gnugrep
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail

      CACHE_DIR="/tmp/repo-browse-cache''${USER:+.$USER}"

      usage() {
        echo "usage: repo-browse <ls|cat|grep|tree> <git-url> [path|pattern]" >&2
        echo "  ls   <url> [path]     — list directory contents" >&2
        echo "  cat  <url> <path>     — read a specific file" >&2
        echo "  grep <url> <pattern>  — search file contents" >&2
        echo "  tree <url> [path]     — show directory tree" >&2
        echo "  Works with GitHub, GitLab, Codeberg, Gitea, and any git host." >&2
        exit 1
      }

      [ $# -lt 2 ] && usage

      cmd=$1
      url=$2
      shift 2

      # Sanitize URL for use as cache directory name
      cache_key=$(printf '%s' "$url" | sed 's|[^a-zA-Z0-9._-]|_|g')
      repo_dir="$CACHE_DIR/$cache_key"

      clone_repo() {
        if [ ! -d "$repo_dir/.git" ]; then
          mkdir -p "$CACHE_DIR"
          echo "[repo-browse] cloning $url ..." >&2
          git clone --depth 1 "$url" "$repo_dir" >&2
        fi
      }

      case "$cmd" in
        ls)
          target_path="''${1:-.}"
          clone_repo
          ls -la "$repo_dir/$target_path"
          ;;
        cat)
          [ $# -lt 1 ] && usage
          clone_repo
          cat "$repo_dir/$1"
          ;;
        grep)
          [ $# -lt 1 ] && usage
          pattern=$1
          clone_repo
          cd "$repo_dir"
          git grep -n "$pattern" || grep -rn "$pattern" . --exclude-dir=.git
          ;;
        tree)
          target_path="''${1:-.}"
          clone_repo
          find "$repo_dir/$target_path" -not -path '*/.git/*' | sed "s|^$repo_dir/||" | sort
          ;;
        *)
          echo "unknown command: $cmd" >&2
          usage
          ;;
      esac
    '';
  };

  # Homelab-secret-backed extensions (vault-agent / LAN). Filtered out of
  # the store-path extensions dir when homelabExtensions.enable = false.
  homelabExtensionFiles = [
    "nvidia-nim.ts"
    "usage-tracker.ts"
  ];

  # Immutable filtered extensions: every file from the tracked tree except
  # the homelab-secret ones above. lib/ stays intact. Used only when
  # homelabExtensions.enable = false; default true keeps the out-of-store
  # whole-directory symlink for Aragorn/workstations.
  piExtensionsFiltered = pkgs.runCommand "pi-extensions-filtered" { } ''
    mkdir -p "$out"
    cp -a ${./pi-coding-agent/extensions}/. "$out/"
    chmod -R u+w "$out"
    ${lib.concatMapStrings (f: ''
      rm -f "$out/${f}"
    '') homelabExtensionFiles}
  '';

  # Desktop control package (@amaster.ai/pi-computer-use). Built from npm
  # tarball + staged lockfile; host-gated via computerUse.enable. Full
  # logged-in desktop access — enable only on hosts that should expose it
  # (currently Denethor).
  piComputerUse = pkgs.buildNpmPackage {
    pname = "pi-computer-use";
    version = "0.1.6";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@amaster.ai/pi-computer-use/-/pi-computer-use-0.1.6.tgz";
      hash = "sha512-C3hUzx86nT10DXC97be5hpb0UeopTxgvEomBj4riEPMZ46USyLIXYli4CCHpWg0bLpPPdRAYxUldu67zJoAx7g==";
    };
    postPatch = ''
      ${pkgs.jq}/bin/jq 'del(.devDependencies)' package.json > package.json.new
      mv package.json.new package.json
      cp ${./pi-coding-agent/pi-computer-use-package-lock.json} package-lock.json
    '';
    npmDepsHash = "sha256-nVtNkAuZgIJAgrnBp5GxPmrYqIdS7qtwkzcm4nyEbA8=";
    npmFlags = [ "--legacy-peer-deps" ];
    dontNpmBuild = true;
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.libx11
      pkgs.libxi
      pkgs.libxkbcommon
      pkgs.stdenv.cc.cc.lib
    ];
    postInstall = ''
      rm -rf $out/lib/node_modules/@amaster.ai/pi-computer-use/bin/darwin-universal
      rm -rf $out/lib/node_modules/@amaster.ai/pi-computer-use/bin/win32-x64
      rm -rf $out/lib/node_modules/@amaster.ai/pi-computer-use/bin/win32-arm64
      rm -rf $out/lib/node_modules/@amaster.ai/pi-computer-use/bin/linux-arm64
    '';
  };
  piComputerUseRoot = "${piComputerUse}/lib/node_modules/@amaster.ai/pi-computer-use";

  # Declarative settings for programs.pi-coding-agent (read-only store path).
  # When computerUse.enable, append the store package path + CUA config.
  # The package asks before launching apps and six high-risk actions.
  # Screen reads, clicks, typing, and browser driving stay unprompted.
  piSettings = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    enabledModels =
      let
        all = [
          "claude-bridge/claude-fable-5"
          "claude-bridge/claude-opus-5"
          "xai-auth/grok-4.5"
          "zai/glm-5.2"
          "opencode-go/minimax-m3"
          "opencode-go/deepseek-v4-pro"
          "opencode-go/deepseek-v4-flash"
          "openai-codex/gpt-5.6-sol"
        ];
        blockedPrefixes = [
          "kimi-coding/"
          "zai/"
          "opencode-go/"
        ];
      in
      if cfg.homelabProviders.enable then
        all
      else
        builtins.filter (model: !lib.any (prefix: lib.hasPrefix prefix model) blockedPrefixes) all;
    theme = "gruvbox-material";
    lastChangelogVersion = pkgs.llm-agents.pi.version;
    packages = [
      "git:github.com/annapurna-himal/pi-vim-editor"
      "npm:pi-mermaid"
      "npm:pi-btw"
      "npm:pi-init"
      "git:github.com/DietrichGebert/ponytail"
      "npm:pi-caveman"
      "npm:pi-claude-bridge"
      "npm:pi-mcp-adapter"
      "npm:@tintinweb/pi-subagents"
      {
        source = "git:github.com/anthropics/skills";
        skills = [ "skills/frontend-design/**" ];
      }
      "npm:pi-xai-oauth"
      "npm:pi-sense"
    ]
    ++ lib.optionals cfg.computerUse.enable [ piComputerUseRoot ];
    extensions = [
      "${config.home.homeDirectory}/.pi/agent/git/github.com/annapurna-himal/pi-vim-editor/index.ts"
    ];
    hideThinkingBlock = false;
    defaultThinkingLevel = "high";
  }
  // lib.optionalAttrs cfg.computerUse.enable {
    "pi-computer-use" = {
      mode = "bundled";
      confirmAppLaunch = true;
      confirmDangerousActions = true;
    };
  };

  # Homelab providers read vault-agent secrets at runtime. Gated so
  # portable hosts ship a valid empty providers map with no /run/secrets
  # strings. OAuth/default Pi + Claude bridge stay always-on.
  # Passed to programs.pi-coding-agent.models (official HM writes models.json).
  piModelSettings = {
    providers =
      if cfg.homelabProviders.enable then
        {
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
            compat = {
              supportsLongCacheRetention = false;
            };
          };

          # z.ai's Coding-PaaS endpoint (openai-completions protocol).
          # Different from claude-glm's api.z.ai/api/anthropic — pi doesn't
          # need Anthropic-protocol-everywhere like Claude Code does, so the
          # native PaaS endpoint is the right default.
          # Pi knows GLM-5.2's protocol and thinking-level metadata; only its
          # stale context-window value needs overriding.
          zai = {
            apiKey = "!cat /run/secrets/zai_api_key";
            baseUrl = "https://api.z.ai/api/coding/paas/v4";
            modelOverrides."glm-5.2".contextWindow = 1000000;
          };

          # OpenCode Go ($10/month) — pi's built-in opencode-go provider.
          # Same !cat /run/secrets/* pattern as kimi-coding and zai.
          # Renders to /run/secrets/opencode_api_key by vault-agent
          # (see hosts/_profiles/workstation/configuration.nix).
          #
          # Pi already knows the baseUrl, model IDs, and API protocols for
          # opencode-go — some models use openai-completions at
          # /zen/go/v1, others use anthropic-messages at /zen/go.
          # We only supply apiKey + modelOverrides (which satisfies the
          # model-registry's "must specify one of…" check).
          #
          # IMPORTANT: do NOT set a provider-level baseUrl here — it
          # overrides the per-model built-in base URLs and breaks models
          # that use a different API protocol/path (e.g. minimax-m3 uses
          # anthropic-messages at /zen/go, not /zen/go/v1).
          "opencode-go" = {
            apiKey = "!cat /run/secrets/opencode_api_key";
            modelOverrides = {
              "kimi-k2.6" = {
                compat = {
                  supportsLongCacheRetention = false;
                };
              };
              # MiniMax M3 (launched 2026-06-01) — already in pi's built-in
              # registry; we override context window sizes from OpenCode
              # Go's /models endpoint. Pi uses these to populate
              # --list-models and enforce context limits.
              "minimax-m3" = {
                contextWindow = 512 * 1024; # 512K on OpenCode Go (full 1M needs direct MiniMax plan)
                maxOutputTokens = 131072; # 128K output, same as minimax-m2.7
              };
            };
          };
        }
      else
        { };
  };

  # Thin wrapper around pkgs.llm-agents.pi so we can inject flags
  # (DISPLAY/CUA on computerUse hosts) before the real binary.
  piPackage = pkgs.writeShellScriptBin "pi" ''
    ${lib.optionalString cfg.computerUse.enable ''
      # Denethor's LightDM autologin desktop. Keep an explicit DISPLAY
      # (for example SSH forwarding) when the caller already supplied one.
      export DISPLAY="''${DISPLAY:-:0}"
      export CUA_TELEMETRY_ENABLED=false
    ''}
    exec ${pkgs.llm-agents.pi}/bin/pi "$@"
  '';
  # Claude Agent SDK normally loads Claude Code's user, project, and local
  # settings when settingSources is omitted. pi-claude-bridge 0.6.2 ignores
  # its settingSources config, so inject the equivalent CLI flag through a
  # dedicated executable wrapper. The post-update activation preserves the
  # stock Claude Code system-prompt preset: replacing it with Pi's full prompt
  # makes subscription requests require extra usage. The bridge still appends
  # AGENTS.md and skills through systemPromptAppend. Wrapper still excludes ~/.claude
  # settings/hooks, Claude filesystem instructions, project CLAUDE.md
  # duplication, and Claude auto-memory. Managed policy and ~/.claude.json
  # runtime/auth state still load by Agent SDK design.
  #
  # The second wrapper hop is also required on NixOS: the SDK's bundled
  # musl/glibc binary cannot run here, while ~/.local/bin/claude points to
  # the Nix-managed Claude Code wrapper from claude-code.nix.
  claudeBridgeExecutable = pkgs.writeShellScript "claude-bridge-isolated" ''
    export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
    exec ${config.home.homeDirectory}/.local/bin/claude --setting-sources "" "$@"
  '';

  # Read-only bridge config; unlike Pi's mutable settings.json, a store-path
  # source is the honest shape. Keep settingSources declared as well so a
  # future bridge release that honors it makes the wrapper flag redundant.
  piClaudeBridgeConfig = pkgs.writeText "pi-claude-bridge.json" (
    builtins.toJSON {
      provider = {
        pathToClaudeCodeExecutable = "${claudeBridgeExecutable}";
        settingSources = [ ];
      };
      # AskClaude tool disabled — it spawns a separate Claude Code session
      # that competes with the main Fable session for Claude quota. The
      # model-router skill + scout/worker/reviewer agents cover delegation
      # without burning Claude tokens on a second concurrent session.
      askClaude.enabled = false;
    }
  );

  # ─── Browser automation (chrome-devtools-mcp via pi-mcp-adapter) ─────────
  #
  # pi-mcp-adapter (nicopreme, `pi install npm:pi-mcp-adapter`) exposes MCP
  # servers as ONE lazy proxy tool (~200 tokens) instead of registering every
  # server's tools up-front — directly addresses Mario's MCP token-bloat
  # objection ("what if you don't need MCP"). Servers start on first call,
  # idle-disconnect; the agent does `mcp({ search: "screenshot" })` then
  # `mcp({ tool: "...", args: '{}' })`.
  #
  # We drive chrome-devtools-mcp (Google) rather than @playwright/mcp here:
  # playwright-mcp bundles its own playwright-core which expects specific
  # browser REVISIONS, and its downloads don't run on NixOS (unpatched,
  # missing libnss3/libnspr4). nixpkgs ships patched playwright browsers, but
  # only at its pinned playwright version (1.60.0); @playwright/mcp@latest
  # bundles 1.62-alpha → revision mismatch → hard failure. chrome-devtools-mcp
  # sidesteps all of that: --executable-path points it at nixpkgs' already-
  # Nix-patched system Chromium via CDP. Zero browser download, zero patchelf,
  # zero version coupling. Chrome-only is fine for hitting localhost dev
  # servers (the web-dev testing use case); reach for playwright-mcp only if
  # firefox/webkit test matrices become load-bearing.
  #
  # `${pkgs.nodejs}` and `${pkgs.chromium}` interpolate at BUILD time (JSON
  # can't interpolate at runtime) — same store-path pattern as
  # piClaudeBridgeConfig. npx -y ...@latest mirrors the tavily-mcp pattern in
  # claude-code.nix. lifecycle=lazy is the adapter default but stated for
  # clarity. --headless = no visible window; drop it when you want eyes on
  # the page while the agent drives it.
  piMcp = pkgs.writeText "mcp.json" (
    builtins.toJSON {
      mcpServers = {
        "chrome-devtools" = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [
            "-y"
            "chrome-devtools-mcp@latest"
            "--headless"
            "--executable-path"
            "${pkgs.chromium}/bin/chromium"
          ];
          lifecycle = "lazy";
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

in
{
  options.piCodingAgent = {
    searxngUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://searxng.lan";
      description = ''
        Base URL for the web-search CLI's SearXNG endpoint (no trailing path).
        Set to null on hosts that must not contact or embed searxng.lan;
        web-search then fails fast with a not-configured message.
      '';
    };

    homelabProviders.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Include models.json provider entries that read vault-agent secrets
        at /run/secrets/{kimi_code,zai,opencode}_api_key. Set false on
        isolated hosts (e.g. Denethor); models.json then has an empty
        providers map and no /run/secrets strings. Settings also omit models
        backed by those unavailable providers. OAuth models and the Claude
        bridge stay on.
      '';
    };

    homelabExtensions.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true (default), .pi/agent/extensions is an out-of-store symlink
        into the dotfiles working tree. When false, use a generated immutable
        filtered directory that excludes nvidia-nim.ts and usage-tracker.ts
        (homelab-secret-backed integrations). All other extension files and
        lib/ remain. Set false on isolated hosts (e.g. Denethor).
      '';
    };

    # Host-specific: full logged-in desktop access via Cua Driver. Only enable
    # on machines that should expose the session to Pi (e.g. Denethor work VM).
    computerUse.enable = lib.mkEnableOption "Pi desktop control through Cua Driver";
  };

  # numtide/llm-agents.nix's default overlay namespaces everything under
  # pkgs.llm-agents.* (not top-level pkgs.pi).
  #
  # Official programs.pi-coding-agent owns package + settings.json +
  # models.json (read-only store paths). Companion module keeps options,
  # helpers, extensions/resources, theme, MCP, bridge, CUA, activations.
  #
  # extensions/, prompts/, skills/, and other resources stay OUT-OF-STORE
  # symlinks into the dotfiles working tree so pi's `/reload` and similar
  # land in git. Changing SHAPE still needs `nh home switch`.
  #
  # pi also writes ~/.pi/agent/{auth.json,sessions/} at runtime — NOT
  # managed here, pi owns that mutable state.
  config = {
    programs.pi-coding-agent = {
      enable = true;
      package = piPackage;
      settings = piSettings;
      models = piModelSettings;
    };

    home = {
      # Keep pi extensions current on every home switch. Network call —
      # best-effort so offline/dry-run switches still succeed.
      #
      # piPatchClaudeBridge runs after that: pi installs pi-claude-bridge
      # mutably under ~/.pi/agent/npm/node_modules, so each update can
      # restore stock models.ts. Patch it to expose claude-opus-5 until
      # pi-ai/bridge ship it: order it before older Opus, synthesize metadata
      # from the prior Opus entry, and map the runtime id to claude-opus-5[1m].
      # Bare Opus 5 only serves a 200K window, so pi would register 1M and
      # compact at the real limit instead. [1m] serves the full window and stays
      # on included Max usage (verified while extra usage is disabled).
      #
      # Keep bridge's stock Claude Code system-prompt preset. Replacing it with
      # Pi's full third-party harness prompt makes subscription-backed requests
      # require extra usage. The stock bridge still appends AGENTS.md and skills.
      activation = {
        piUpdateExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.llm-agents.pi}/bin/pi update --extensions || echo "pi: extension update failed (offline?), skipping" >&2
        '';

        piPatchClaudeBridge = lib.hm.dag.entryAfter [ "piUpdateExtensions" ] ''
                  bridge_src="$HOME/.pi/agent/npm/node_modules/pi-claude-bridge/src"
                  index_ts="$bridge_src/index.ts"
                  models_ts="$bridge_src/models.ts"

                  # Undo the old full-Pi-system-prompt patch. Claude subscription
                  # usage requires the stock Claude Code preset; bridge still
                  # appends AGENTS.md and skills through systemPromptAppend.
                  if [ -f "$index_ts" ]; then
                    run ${pkgs.python3}/bin/python3 - "$index_ts" <<'PY'
          import sys
          from pathlib import Path

          path = Path(sys.argv[1])
          text = path.read_text()
          old = "\t\tsystemPrompt: context.systemPrompt,\n\t\textraArgs,"
          stock = (
              "\t\tsystemPrompt: {\n"
              "\t\t\ttype: \"preset\", preset: \"claude_code\",\n"
              "\t\t\tappend: systemPromptAppend ? systemPromptAppend : undefined,\n"
              "\t\t},\n"
              "\t\textraArgs,"
          )
          old_count = text.count(old)
          stock_count = text.count(stock)
          if old_count == 1 and stock_count == 0:
              path.write_text(text.replace(old, stock, 1))
              print(f"pi: restored {path} stock Claude Code system-prompt preset")
          elif old_count == 0 and stock_count == 1:
              print(f"pi: {path} already uses stock Claude Code system-prompt preset")
          else:
              raise SystemExit(
                  f"pi: {path}: unexpected system-prompt shape; "
                  f"old_count={old_count} stock_count={stock_count}"
              )
          PY
                  fi

                  if [ ! -f "$models_ts" ]; then
                    echo "pi: pi-claude-bridge not installed, skipping Opus 5 patch" >&2
                  else
                    # models.ts: Opus 5 order + metadata synthesize + bare runtime.
                    # Migrates old patched bare runtime; accepts already-desired ids/buildModels.
                    run ${pkgs.python3}/bin/python3 - "$models_ts" <<'PY'
          import sys
          from pathlib import Path

          path = Path(sys.argv[1])
          text = path.read_text()

          stock_ids = (
              'export const MODEL_IDS_IN_ORDER = ["claude-fable-5", "claude-opus-4-8", '
              '"claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-5", '
              '"claude-sonnet-4-6", "claude-haiku-4-5"];'
          )
          desired_ids = (
              'export const MODEL_IDS_IN_ORDER = ["claude-fable-5", "claude-opus-5", '
              '"claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", '
              '"claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-4-5"];'
          )

          stock_build = (
              "export function buildModels<T extends { id: string; [key: string]: any }>(piAiModels: T[]) {\n"
              "\treturn MODEL_IDS_IN_ORDER\n"
              "\t\t.map((id) => piAiModels.find((m) => m.id === id))\n"
              "\t\t.filter((m) => m != null)\n"
          )
          desired_build = (
              "export function buildModels<T extends { id: string; [key: string]: any }>(piAiModels: T[]) {\n"
              "\treturn MODEL_IDS_IN_ORDER\n"
              "\t\t.map((id) => {\n"
              "\t\t\tconst found = piAiModels.find((m) => m.id === id);\n"
              "\t\t\tif (found) return found;\n"
              "\t\t\t// pi-ai lacks Opus 5 metadata: reuse Opus 4.8 fields, override id/name.\n"
              "\t\t\tif (id === \"claude-opus-5\") {\n"
              "\t\t\t\tconst base = piAiModels.find((m) => m.id === \"claude-opus-4-8\");\n"
              "\t\t\t\tif (!base) return undefined;\n"
              "\t\t\t\treturn { ...base, id: \"claude-opus-5\", name: \"Claude Opus 5\" };\n"
              "\t\t\t}\n"
              "\t\t\treturn undefined;\n"
              "\t\t})\n"
              "\t\t.filter((m) => m != null)\n"
          )

          stock_runtime = (
              '\t\tcase "claude-opus-4-8":\n'
              '\t\t\treturn { cliModelId: "claude-opus-4-8[1m]", contextWindow: ONE_M_CONTEXT };'
          )
          old_patched_runtime = (
              '\t\tcase "claude-opus-5":\n'
              '\t\t\treturn { cliModelId: "claude-opus-5", contextWindow: ONE_M_CONTEXT };\n'
              '\t\tcase "claude-opus-4-8":\n'
              '\t\t\treturn { cliModelId: "claude-opus-4-8[1m]", contextWindow: ONE_M_CONTEXT };'
          )
          desired_runtime = (
              '\t\tcase "claude-opus-5":\n'
              '\t\t\treturn { cliModelId: "claude-opus-5[1m]", contextWindow: ONE_M_CONTEXT };\n'
              '\t\tcase "claude-opus-4-8":\n'
              '\t\t\treturn { cliModelId: "claude-opus-4-8[1m]", contextWindow: ONE_M_CONTEXT };'
          )

          def once(label, *variants):
              # Longer first: stock_runtime is a suffix of old-patched/desired
              # runtime blocks. Accept substring hits of an already-matched
              # longer variant; reject two independent shapes.
              matched = None
              for v in sorted(variants, key=len, reverse=True):
                  n = text.count(v)
                  if n == 0:
                      continue
                  if n != 1:
                      raise SystemExit(
                          f"pi: {path}: {label}: variant duplicated (count={n}); "
                          f"bridge shape changed?"
                      )
                  if matched is not None:
                      if v in matched:
                          continue
                      raise SystemExit(
                          f"pi: {path}: {label}: multiple independent shapes present; "
                          f"bridge shape changed?"
                      )
                  matched = v
              if matched is None:
                  raise SystemExit(
                      f"pi: {path}: {label}: none of stock/old-patched/desired found; "
                      f"bridge shape changed?"
                  )
              return matched

          ids = once("model ids", stock_ids, desired_ids)
          build = once("buildModels", stock_build, desired_build)
          runtime = once("runtime map", stock_runtime, old_patched_runtime, desired_runtime)

          # Partial desired (e.g. old bare runtime + desired ids) still needs migrate.
          changed = []
          if ids != desired_ids:
              text = text.replace(ids, desired_ids, 1)
              changed.append("ids")
          if build != desired_build:
              text = text.replace(build, desired_build, 1)
              changed.append("buildModels")
          if runtime != desired_runtime:
              text = text.replace(runtime, desired_runtime, 1)
              changed.append("runtime")
          path.write_text(text)
          print(
              f"pi: patched {path} for claude-opus-5[1m] "
              f"({'+'.join(changed) or 'noop'}; bare Opus 5 only serves 200K)"
          )
          PY
                  fi
        '';
      };

      packages = [
        # Pi installs and updates npm-based extensions at runtime.
        # (pi binary itself comes from programs.pi-coding-agent.package)
        pkgs.nodejs

        webSearch
        webFetch
        webFetchJina
        repoIngest
        repoBrowse

        # Structural code search via tree-sitter. No wrapper — ast-grep's
        # CLI is already clean (`ast-grep run -l python -p '...'`). The
        # code-nav skill teaches the model when to reach for it over rg
        # (definition/reference lookups, structural shapes).
        pkgs.ast-grep

        # Paren checker for Emacs Lisp the agent writes. See the comment
        # on the derivation above and skills/elisp/SKILL.md.
        agent-lisp-paren-aid
      ];
      sessionVariables.PI_CACHE_RETENTION = "long";
      file = {
        ".pi/agent/extensions".source =
          if cfg.homelabExtensions.enable then
            config.lib.file.mkOutOfStoreSymlink "${piUserDir}/extensions"
          else
            piExtensionsFiltered;
        ".pi/agent/agents".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/agents";
        ".pi/agent/agent-tool-description.md".source =
          config.lib.file.mkOutOfStoreSymlink "${piUserDir}/agent-tool-description.md";
        ".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/prompts";
        ".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/skills";
        ".pi/agent/APPEND_SYSTEM.md".source =
          config.lib.file.mkOutOfStoreSymlink "${piUserDir}/APPEND_SYSTEM.md";
        ".pi/agent/caveman.json".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/caveman.json";
        ".pi/agent/subagents.json".source =
          config.lib.file.mkOutOfStoreSymlink "${piUserDir}/subagents.json";
        ".pi/agent/pi-sense.json".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/pi-sense.json";
        ".pi/agent/claude-bridge.json".source = piClaudeBridgeConfig;
        ".pi/agent/mcp.json".source = piMcp;
        ".pi/agent/themes/gruvbox-material.json".source = piTheme;
      };
    };
  };
}
