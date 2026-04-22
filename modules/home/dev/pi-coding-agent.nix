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
  # extensions/, prompts/, skills/ are OUT-OF-STORE symlinks pointing
  # into the dotfiles working tree so pi's `/reload` picks up in-session
  # edits and pi-written files land directly in git. Changing the
  # SHAPE (adding a folder, bumping the package) still needs
  # `nh home switch`; iterating on individual files does not.
  #
  # pi also writes into ~/.pi/agent/{auth.json,sessions/,settings.json}
  # at runtime — NOT symlinked here, pi manages them as mutable state.
  home = {
    packages = [ pkgs.llm-agents.pi ];
    sessionVariables.PI_CACHE_RETENTION = "long";
    file = {
      ".pi/agent/models.json".source = piModels;
      ".pi/agent/extensions".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/extensions";
      ".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/prompts";
      ".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${piUserDir}/skills";
    };
  };
}
