# Pippin Home Manager configuration
#
# Declarative openclaw config via nix-openclaw module.
# Secrets are injected at service start via ExecStartPre (never in Nix store).
{
  lib,
  pkgs,
  ...
}:

let
  # Upstream packaging bug: docs/reference/templates/ not included in gateway.
  # (https://gist.github.com/gudnuf/8fe65ca0e49087105cb86543dc8f0799)
  # We patch the gateway and set it as the instance package directly, which
  # bypasses the module's defaultPackage → withTools → reimport chain that
  # would otherwise discard our override (lib.nix:14-17).
  patchedGateway = pkgs.openclaw-gateway.overrideAttrs (old: {
    installPhase = ''
      ${old.installPhase}
      mkdir -p $out/lib/openclaw/docs/reference/templates
      cp -r $src/docs/reference/templates/* $out/lib/openclaw/docs/reference/templates/
    '';
  });

  # Inject SOPS secrets into a runtime copy of the HM-generated config.
  # The HM-managed openclaw.json symlink is never modified — secrets go into
  # openclaw-runtime.json, and OPENCLAW_CONFIG_PATH points the service there.
  coreutils = "${pkgs.coreutils}/bin";
  runtimeConfig = "$HOME/.openclaw/openclaw-runtime.json";
  injectSecrets = pkgs.writeShellScript "openclaw-inject-secrets" ''
    set -euo pipefail
    SOURCE="$HOME/.openclaw/openclaw.json"
    RUNTIME="${runtimeConfig}"

    if [ ! -e "$SOURCE" ]; then
      echo "ERROR: $SOURCE does not exist" >&2
      exit 1
    fi

    # Copy HM config to mutable runtime location (resolves symlinks)
    ${coreutils}/cp -L "$SOURCE" "$RUNTIME"
    ${coreutils}/chmod 600 "$RUNTIME"

    # Read secrets from SOPS-decrypted files
    TELEGRAM_TOKEN=$(${coreutils}/cat /run/secrets/telegram_bot_token)
    BIFROST_KEY=$(${coreutils}/cat /run/secrets/bifrost_api_key)
    ELEVENLABS_KEY=$(${coreutils}/cat /run/secrets/elevenlabs_api_key)

    # Inject secrets into runtime config
    ${lib.getExe pkgs.jq} \
      --arg tt "$TELEGRAM_TOKEN" \
      --arg bk "$BIFROST_KEY" \
      --arg ek "$ELEVENLABS_KEY" \
      '
        .channels.telegram.accounts.d43m0n.botToken = $tt |
        .models.providers.bifrost.apiKey = $bk |
        .agents.defaults.memorySearch.remote.apiKey = $bk |
        .messages.tts.elevenlabs.apiKey = $ek
      ' "$RUNTIME" > "$RUNTIME.tmp"

    ${coreutils}/mv "$RUNTIME.tmp" "$RUNTIME"
    ${coreutils}/chmod 600 "$RUNTIME"
    echo "Secrets injected into openclaw-runtime.json"
  '';
in
{
  imports = [
    ../../../hosts/profiles/essentials/home.nix
  ];

  programs.openclaw = {
    enable = true;

    # Use patched gateway directly as instance package to:
    # 1. Include workspace templates (upstream packaging bug)
    # 2. Bypass module's defaultPackage → withTools reimport (lib.nix:14-17)
    #    that discards overlay overrides when programs.git.enable triggers
    #    toolOverridesEnabled, causing withTools to reimport from source.
    instances.default.package = patchedGateway;

    # Config lives inside the instance to avoid a nix-openclaw module bug:
    # lib.recursiveUpdate with a submodule-evaluated instance config (all nulls)
    # overwrites the global cfg.config values before stripNulls can preserve them.
    instances.default.config = {
      # Gateway
      gateway = {
        mode = "local";
        bind = "lan";
        auth.token = "pippin-gateway-token";
        remote.token = "pippin-gateway-token";
        trustedProxies = [
          "192.168.1.21"
          "192.168.1.50"
        ];
      };

      # Bifrost provider (OpenAI-compatible LLM gateway)
      models.providers.bifrost = {
        baseUrl = "https://bifrost.dimensiondoor.xyz/v1";
        apiKey = "SOPS_PLACEHOLDER"; # injected at runtime
        api = "openai-completions";
        models = [
          {
            id = "deepseek/deepseek-chat";
            name = "DeepSeek V3";
            api = "openai-completions";
            reasoning = false;
            input = [ "text" ];
            cost = {
              input = 0;
              output = 0;
              cacheRead = 0;
              cacheWrite = 0;
            };
            contextWindow = 64000;
            maxTokens = 8000;
          }
          {
            id = "deepseek/deepseek-reasoner";
            name = "DeepSeek R1";
            api = "openai-completions";
            reasoning = true;
            input = [ "text" ];
            cost = {
              input = 0;
              output = 0;
              cacheRead = 0;
              cacheWrite = 0;
            };
            contextWindow = 64000;
            maxTokens = 8000;
          }
          {
            id = "zai/glm-4.7";
            name = "GLM 4.7";
            api = "openai-completions";
            reasoning = false;
            input = [ "text" ];
            cost = {
              input = 0;
              output = 0;
              cacheRead = 0;
              cacheWrite = 0;
            };
            contextWindow = 200000;
            maxTokens = 128000;
          }
          {
            id = "cliproxy/kimi-for-coding";
            name = "Kimi K2.5 (Coder)";
            api = "openai-completions";
            reasoning = false;
            input = [ "text" ];
            cost = {
              input = 0;
              output = 0;
              cacheRead = 0;
              cacheWrite = 0;
            };
            contextWindow = 262144;
            maxTokens = 32768;
            compat.supportsDeveloperRole = false;
          }
        ];
      };

      # Agent configuration (D43M0N only)
      agents = {
        defaults = {
          model.primary = "bifrost/cliproxy/kimi-for-coding";
          memorySearch = {
            provider = "openai";
            model = "ollama/nomic-embed-text";
            remote = {
              baseUrl = "https://bifrost.dimensiondoor.xyz/v1";
              apiKey = "SOPS_PLACEHOLDER"; # injected at runtime
            };
          };
        };
        list = [
          {
            id = "main";
            name = "D43M0N";
          }
        ];
      };

      # Agent-channel bindings (top-level config key)
      bindings = [
        {
          agentId = "main";
          match = {
            channel = "telegram";
            accountId = "d43m0n";
          };
        }
      ];

      # Telegram (D43M0N only)
      channels.telegram = {
        accounts.d43m0n = {
          botToken = "SOPS_PLACEHOLDER"; # injected at runtime
          dmPolicy = "allowlist";
          allowFrom = [ "6341127220" ];
        };
      };

      # ElevenLabs TTS
      messages.tts = {
        provider = "elevenlabs";
        auto = "always";
        modelOverrides = {
          enabled = true;
          allowProvider = true;
        };
        elevenlabs = {
          apiKey = "SOPS_PLACEHOLDER"; # injected at runtime
          voiceId = "7IggYPBduXWgroMBqf5S";
          modelId = "eleven_multilingual_v2";
          voiceSettings = {
            stability = 0.3;
            similarityBoost = 0.8;
            style = 0.4;
            useSpeakerBoost = true;
            speed = 1.0;
          };
        };
      };
    };
  };

  # Override the openclaw systemd user service to:
  # 1. Inject secrets into a runtime config copy before start
  # 2. Point openclaw at the runtime config (not the HM-managed symlink)
  # 3. Auto-start on boot via default.target
  systemd.user.services.openclaw-gateway = {
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStartPre = lib.mkBefore [ "${injectSecrets}" ];
      Environment = [
        "SHARP_IGNORE_GLOBAL_LIBVIPS=1"
        "OPENCLAW_CONFIG_PATH=%h/.openclaw/openclaw-runtime.json"
        "MOLTBOT_CONFIG_PATH=%h/.openclaw/openclaw-runtime.json"
        "CLAWDBOT_CONFIG_PATH=%h/.openclaw/openclaw-runtime.json"
      ];
    };
  };
}
