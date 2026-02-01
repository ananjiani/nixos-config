# Pippin - Openclaw AI Assistant (Proxmox VM on the-shire)
#
# Dedicated isolated VM for openclaw to safely execute arbitrary commands.
# Uses npm-based installation for simplicity and small footprint.
{
  inputs,
  pkgs-stable,
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/attic-watch-store.nix
  ];

  networking = {
    hostName = "pippin";
    useDHCP = true;
    nameservers = [
      "192.168.1.53" # AdGuard VIP with internal DNS rewrites
      "9.9.9.9" # Quad9 fallback
    ];
    # Allow openclaw web UI access
    firewall.allowedTCPPorts = [ 18789 ];
  };

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_authkey = { };
      telegram_bot_token = { };
      keres_telegram_token = { };
      bifrost_api_key = { };
      tavily_api_key = { };
      elevenlabs_api_key = { };
    };
    # Environment file for openclaw service
    templates."openclaw.env" = {
      content = ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.telegram_bot_token}
        KERES_TELEGRAM_TOKEN=${config.sops.placeholder.keres_telegram_token}
        BIFROST_API_KEY=${config.sops.placeholder.bifrost_api_key}
        TAVILY_API_KEY=${config.sops.placeholder.tavily_api_key}
        PERSONA_MCP_URL=https://mcp.persona.lan/mcp
        ELEVENLABS_API_KEY=${config.sops.placeholder.elevenlabs_api_key}
      '';
    };
  };

  modules = {
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      acceptDns = false;
      acceptRoutes = false;
      useExitNode = null; # On LAN, no exit node needed
    };

    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Node.js for clawdbot
  environment.systemPackages = with pkgs; [
    nodejs_22
    git
    openssh
    curl
    jq
    # Git platforms
    gh
    codeberg-cli
    # Search/files
    ripgrep
    fd
    tree
    bat
    # Data processing
    yq
    python3
    # Network
    wget
    httpie
    # Archives
    unzip
    zip
    gnutar
    # Browser
    chromium
  ];

  # Clawdbot data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/clawdbot 0755 root root -"
    "d /var/lib/clawdbot/.npm-global 0755 root root -"
  ];

  # Openclaw systemd service
  systemd.services.openclaw = {
    description = "Openclaw AI Assistant";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/var/lib/clawdbot";
      NPM_CONFIG_PREFIX = "/var/lib/clawdbot/.npm-global";
      # Skip native libvips build (uses JS fallback)
      SHARP_IGNORE_GLOBAL_LIBVIPS = "1";
      # Gateway auth token for LAN binding (required by openclaw)
      OPENCWL_GATEWAY_TOKEN = "pippin-gateway-token";
    };

    path = [ "/run/current-system/sw" ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/var/lib/clawdbot";
      EnvironmentFile = config.sops.templates."openclaw.env".path;

      # Allow 10 minutes for initial npm install
      TimeoutStartSec = "10min";

      # Install and setup openclaw
      ExecStartPre = [
        (pkgs.writeShellScript "openclaw-install" ''
          set -euo pipefail
          export PATH=/var/lib/clawdbot/.npm-global/bin:$PATH

          if [ ! -x /var/lib/clawdbot/.npm-global/bin/openclaw ]; then
            echo "Installing openclaw..."
            npm install -g openclaw@latest
          fi

          # Install skills from clawdbot/skills repo (clawdhub is broken)
          install_skill() {
            local skill_path="$1"
            local skill_name="$2"
            if [ ! -d "$HOME/.openclaw/skills/$skill_name" ]; then
              echo "Installing $skill_name skill from GitHub..."
              mkdir -p "$HOME/.openclaw/skills"
              cd "$HOME/.openclaw/skills"
              rm -rf _temp_skills
              git clone --depth 1 --filter=blob:none --sparse https://github.com/clawdbot/skills.git _temp_skills
              cd _temp_skills
              git sparse-checkout set "$skill_path"
              mv "$skill_path" ../"$skill_name"
              cd ..
              rm -rf _temp_skills
            fi
          }

          install_skill "skills/arun-8687/tavily-search" "tavily-search"
          install_skill "skills/steipete/github" "github"
          install_skill "skills/steipete/weather" "weather"
        '')
        (pkgs.writeShellScript "openclaw-setup" ''
          set -euo pipefail
          export PATH=/var/lib/clawdbot/.npm-global/bin:$PATH

          CONFIG="$HOME/.openclaw/openclaw.json"

          # Bootstrap config if it doesn't exist
          if [ ! -f "$CONFIG" ]; then
            echo "Running initial openclaw setup..."
            openclaw doctor --fix --non-interactive || true
          fi

          # Declarative config management — Nix is source of truth
          if [ -f "$CONFIG" ]; then
            node -e "
              const fs = require('fs');
              const config = JSON.parse(fs.readFileSync('$CONFIG'));

              // Gateway: merge to preserve runtime state (paired devices etc.)
              const token = process.env.OPENCWL_GATEWAY_TOKEN;
              config.gateway = config.gateway || {};
              config.gateway.auth = { token };
              config.gateway.remote = { token };
              config.gateway.mode = 'local';
              config.gateway.trustedProxies = ['192.168.1.21', '192.168.1.50'];
              console.log('Gateway configured');

              // Bifrost provider (OpenAI-compatible LLM gateway)
              config.models = config.models || {};
              config.models.providers = config.models.providers || {};
              config.models.providers.bifrost = {
                baseUrl: 'https://bifrost.dimensiondoor.xyz/v1',
                apiKey: process.env.BIFROST_API_KEY,
                api: 'openai-completions',
                models: [
                  {
                    id: 'deepseek/deepseek-chat',
                    name: 'DeepSeek V3',
                    api: 'openai-completions',
                    reasoning: false,
                    input: ['text'],
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    contextWindow: 64000,
                    maxTokens: 8000
                  },
                  {
                    id: 'deepseek/deepseek-reasoner',
                    name: 'DeepSeek R1',
                    api: 'openai-completions',
                    reasoning: true,
                    input: ['text'],
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    contextWindow: 64000,
                    maxTokens: 8000
                  },
                  {
                    id: 'zai/glm-4.7',
                    name: 'GLM 4.7',
                    api: 'openai-completions',
                    reasoning: false,
                    input: ['text'],
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    contextWindow: 200000,
                    maxTokens: 128000
                  },
                  {
                    id: 'cliproxy/kimi-for-coding',
                    name: 'Kimi K2.5 (Coder)',
                    api: 'openai-completions',
                    reasoning: false,
                    input: ['text'],
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                    contextWindow: 262144,
                    maxTokens: 32768,
                    compat: { supportsDeveloperRole: false }
                  }
                ]
              };
              console.log('Bifrost provider configured');

              // Agent defaults
              config.agents = config.agents || {};
              config.agents.defaults = config.agents.defaults || {};
              config.agents.defaults.model = { primary: 'bifrost/cliproxy/kimi-for-coding' };
              config.agents.defaults.memorySearch = {
                provider: 'openai',
                model: 'ollama/nomic-embed-text',
                remote: {
                  baseUrl: 'https://bifrost.dimensiondoor.xyz/v1',
                  apiKey: process.env.BIFROST_API_KEY
                }
              };
              console.log('Memory search embeddings configured via Bifrost/Ollama');

              // Multi-account Telegram setup: D43M0N + Keres
              config.channels = config.channels || {};
              config.channels.telegram = {
                enabled: true,
                accounts: {
                  d43m0n: {
                    name: 'D43M0N',
                    botToken: process.env.TELEGRAM_BOT_TOKEN,
                    dmPolicy: 'allowlist',
                    allowFrom: ['6341127220']
                  },
                  keres: {
                    name: 'Keres',
                    botToken: process.env.KERES_TELEGRAM_TOKEN,
                    dmPolicy: 'allowlist',
                    allowFrom: ['6341127220']
                  }
                }
              };
              console.log('Multi-account Telegram configured (D43M0N + Keres)');

              // Agent bindings: route each Telegram account to its agent
              config.agents.list = [
                {
                  id: 'main',
                  name: 'D43M0N',
                  description: 'Technical executor and infrastructure daemon'
                },
                {
                  id: 'keres',
                  name: 'Keres',
                  description: 'Persona-driven companion (uses MCP)',
                  skills: ['persona-mcp-bridge']
                }
              ];
              config.agents.bindings = [
                { agentId: 'main', match: { channel: 'telegram', accountId: 'd43m0n' } },
                { agentId: 'main', match: { channel: 'telegram', accountId: 'keres' } }
              ];
              console.log('Agent bindings configured: d43m0n -> main, keres -> keres');

              // ElevenLabs TTS with model overrides for multi-voice support
              config.messages = config.messages || {};
              config.messages.tts = {
                provider: 'elevenlabs',
                auto: 'always',
                modelOverrides: {
                  enabled: true,
                  allowProvider: true
                },
                elevenlabs: {
                  apiKey: process.env.ELEVENLABS_API_KEY,
                  voiceId: '7IggYPBduXWgroMBqf5S',
                  modelId: 'eleven_multilingual_v2',
                  voiceSettings: {
                    stability: 0.3,
                    similarityBoost: 0.8,
                    style: 0.4,
                    useSpeakerBoost: true,
                    speed: 1.0
                  }
                }
              };
              console.log('ElevenLabs TTS configured');

              // Clean up stale keys from previous config iterations
              if (config.agents && config.agents.defaults) delete config.agents.defaults.identity;
              if (config.channels && config.channels.telegram) delete config.channels.telegram.systemPrompt;
              console.log('Stale config keys cleaned');

              // TTS expressive tags via workspace SOUL.md
              const workspace = (config.agents && config.agents.defaults && config.agents.defaults.workspace) || String('$HOME/.openclaw/workspace');
              fs.mkdirSync(workspace, { recursive: true });
              const soulPath = workspace + '/SOUL.md';
              const existingSoul = fs.existsSync(soulPath) ? fs.readFileSync(soulPath, 'utf8') : String();
              console.log('SOUL.md TTS instructions ensured');

              // Fix state dir permissions
              fs.chmodSync('$HOME/.openclaw', 0o700);

              fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
            "
          fi
        '')
      ];

      ExecStart = "/var/lib/clawdbot/.npm-global/bin/openclaw gateway --port 18789 --bind lan --allow-unconfigured";

      Restart = "on-failure";
      RestartSec = "10s";

      # Security hardening (middle ground - relaxed filesystem access)
      NoNewPrivileges = true;
      PrivateTmp = true;
      # Note: ProtectSystem and ProtectHome removed to allow full VM management
    };
  };

  services = {
    qemuGuest.enable = true;
    attic-watch-store.enable = true;
  };

  boot = {
    loader.grub.enable = true;
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "virtio_net"
      "sd_mod"
    ];
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
