# Pippin - Clawdbot AI Assistant (Proxmox VM on the-shire)
#
# Dedicated isolated VM for clawdbot to safely execute arbitrary commands.
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
    # Allow clawdbot web UI access
    firewall.allowedTCPPorts = [ 18789 ];
  };

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_authkey = { };
      telegram_bot_token = { };
      bifrost_api_key = { };
      tavily_api_key = { };
    };
    # Environment file for clawdbot service
    templates."clawdbot.env" = {
      content = ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.telegram_bot_token}
        BIFROST_API_KEY=${config.sops.placeholder.bifrost_api_key}
        TAVILY_API_KEY=${config.sops.placeholder.tavily_api_key}
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
    git # Required by clawdbot installer
  ];

  # Clawdbot data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/clawdbot 0755 root root -"
    "d /var/lib/clawdbot/.npm-global 0755 root root -"
  ];

  # Clawdbot systemd service
  systemd.services.clawdbot = {
    description = "Clawdbot AI Assistant";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/var/lib/clawdbot";
      NPM_CONFIG_PREFIX = "/var/lib/clawdbot/.npm-global";
      # Skip native libvips build (uses JS fallback)
      SHARP_IGNORE_GLOBAL_LIBVIPS = "1";
      # Gateway auth token for LAN binding (required by clawdbot)
      CLAWDBOT_GATEWAY_TOKEN = "pippin-gateway-token";
    };

    path = [
      pkgs.nodejs_22
      pkgs.git
      pkgs.coreutils
      pkgs.bash
      pkgs.gnused
      pkgs.gnugrep
      pkgs.gawk
      pkgs.which
      pkgs.findutils
      pkgs.curl
      pkgs.jq
    ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/var/lib/clawdbot";
      EnvironmentFile = config.sops.templates."clawdbot.env".path;

      # Allow 10 minutes for initial npm install
      TimeoutStartSec = "10min";

      # Install and setup clawdbot
      ExecStartPre = [
        (pkgs.writeShellScript "clawdbot-install" ''
          set -euo pipefail
          export PATH=/var/lib/clawdbot/.npm-global/bin:$PATH

          if [ ! -x /var/lib/clawdbot/.npm-global/bin/clawdbot ]; then
            echo "Installing clawdbot..."
            npm install -g clawdbot@latest
          fi

          # Install Tavily search skill if not present
          # Note: clawdhub is broken (missing undici dep), so we use sparse checkout
          if [ ! -d "$HOME/.clawdbot/skills/tavily-search" ]; then
            echo "Installing Tavily search skill from GitHub..."
            mkdir -p "$HOME/.clawdbot/skills"
            cd "$HOME/.clawdbot/skills"
            git clone --depth 1 --filter=blob:none --sparse https://github.com/clawdbot/skills.git _temp_skills
            cd _temp_skills
            git sparse-checkout set skills/arun-8687/tavily-search
            mv skills/arun-8687/tavily-search ../tavily-search
            cd ..
            rm -rf _temp_skills
          fi
        '')
        (pkgs.writeShellScript "clawdbot-setup" ''
          set -euo pipefail
          export PATH=/var/lib/clawdbot/.npm-global/bin:$PATH

          # Only run doctor --fix on first setup (when telegram isn't configured)
          CONFIG="$HOME/.clawdbot/clawdbot.json"
          if [ ! -f "$CONFIG" ] || ! grep -q '"telegram"' "$CONFIG" 2>/dev/null; then
            echo "Running initial clawdbot setup..."
            clawdbot doctor --fix --non-interactive || true
          fi

          # Ensure gateway token and Bifrost provider are in config
          if [ -f "$CONFIG" ]; then
            node -e "
              const fs = require('fs');
              const config = JSON.parse(fs.readFileSync('$CONFIG'));
              let changed = false;

              // Gateway token (for CLI and web UI pairing)
              const token = process.env.CLAWDBOT_GATEWAY_TOKEN;
              if (!config.gateway || config.gateway.auth?.token !== token) {
                config.gateway = {
                  auth: { token },
                  remote: { token }
                };
                changed = true;
                console.log('Gateway token configured');
              }

              // Bifrost provider (OpenAI-compatible LLM gateway)
              // Always overwrite to keep Nix config as source of truth
              config.models = config.models || {};
              config.models.providers = config.models.providers || {};
              config.models.providers.bifrost = {
                  baseUrl: 'https://bifrost.dimensiondoor.xyz/v1',
                  apiKey: process.env.BIFROST_API_KEY,
                  api: 'openai-completions',
                  models: [
                    {
                      id: 'cliproxy/claude-opus-4-5-20251101',
                      name: 'Claude Opus 4.5',
                      api: 'openai-completions',
                      reasoning: true,
                      input: ['text', 'image'],
                      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                      contextWindow: 200000,
                      maxTokens: 64000
                    },
                    {
                      id: 'cliproxy/claude-sonnet-4-5-20250929',
                      name: 'Claude Sonnet 4.5',
                      api: 'openai-completions',
                      reasoning: true,
                      input: ['text', 'image'],
                      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                      contextWindow: 200000,
                      maxTokens: 64000
                    },
                    {
                      id: 'cliproxy/claude-haiku-4-5-20251001',
                      name: 'Claude Haiku 4.5',
                      api: 'openai-completions',
                      reasoning: true,
                      input: ['text', 'image'],
                      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                      contextWindow: 200000,
                      maxTokens: 64000
                    },
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
                      reasoning: true,
                      input: ['text'],
                      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                      contextWindow: 200000,
                      maxTokens: 128000
                    }
              ]
              };
              console.log('Bifrost provider configured');

              config.agents = config.agents || {};
              config.agents.defaults = config.agents.defaults || {};
              config.agents.defaults.model = { primary: 'bifrost/deepseek/deepseek-chat' };

              // Configure embeddings for semantic memory search via Bifrost/Ollama
              config.agents.defaults.memorySearch = {
                provider: 'openai',
                model: 'ollama/nomic-embed-text',
                remote: {
                  baseUrl: 'https://bifrost.dimensiondoor.xyz/v1',
                  apiKey: process.env.BIFROST_API_KEY
                }
              };
              console.log('Memory search embeddings configured via Bifrost/Ollama');

              fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
            "
          fi
        '')
      ];

      ExecStart = "/var/lib/clawdbot/.npm-global/bin/clawdbot gateway --port 18789 --bind lan --allow-unconfigured";

      Restart = "on-failure";
      RestartSec = "10s";

      # Security hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ "/var/lib/clawdbot" ];
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
