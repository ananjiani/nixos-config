# Base terminal configuration used on both servers and desktops
{
  pkgs,
  pkgs-stable,
  ...
}:

{
  home = {
    sessionPath = [ "$HOME/.local/bin" ];

    # Shell aliases
    shellAliases = {
      ls = "eza -a";
      ll = "eza -alh";
      tree = "eza --tree";
      lg = "lazygit";
      cat = "bat";
      df = "duf";
      du = "dust";
      fe = "$EDITOR $(fzf)";
      fv = "vi $(fzf)";
      oc = "npx opencode-ai";
      # claude = "happy";
    };

    packages =
      (with pkgs; [
        # Terminal images
        lsix
        timg
        # Archive tools
        atool
        unrar
        p7zip

        # Media tools
        ffmpeg
        ffmpegthumbnailer

        # Security tools
        gnupg
        pinentry-curses
        rage

        # Text processing
        jq
        pandoc
        poppler-utils

        # System tools
        tealdeer
        dust
        duf
        ripgrep-all
        fd
        sshfs
        lsof
      ])
      ++ (with pkgs-stable; [
        sops
        visidata
      ]);
  };

  programs = {
    # Shells
    bash.enable = true;
    # atuin = {
    #   enable = true;
    #   settings = {
    #     keymap_mode = "vim-normal";
    #     key_path = config.sops.secrets.atuin_key.path;
    #   };
    # };
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        # Vi keybindings
        set -g fish_key_bindings fish_vi_key_bindings
        bind -M insert \cf forward-char
      '';
      functions = {
        fish_title = ''
          hostname
          echo ":"
          prompt_pwd
        '';

        # Wrapper that routes Claude Code through the self-hosted Bifrost
        # LLM gateway, targeting cliproxy's Kimi-for-coding model.
        #
        # Per Kimi Code docs: ENABLE_TOOL_SEARCH=false for Claude Code compatibility.
        # Smoke-tested 2026-04-10: zai and deepseek 404 via Bifrost's Anthropic
        # endpoint because Bifrost translates Messages API → OpenAI Responses API
        # (/v1/responses), which those upstreams don't implement. cliproxy is a
        # flexible passthrough so it works.
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
            claude $argv
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
            claude $argv
        '';
      };
    };

    # Prompt
    starship = {
      enable = true;
      settings = (builtins.fromTOML (builtins.readFile ./nerd-font-symbols.toml)) // {
        add_newline = false;
        line_break.disabled = true;
      };
      package = pkgs-stable.starship;
    };

    # Terminal multiplexer
    zellij = {
      enable = true;
      settings = {
        theme = "gruvbox-dark";
        default_shell = "fish";
        pane_frames = false;
        on_force_close = "quit";
      };
    };

    # File and text tools
    eza = {
      enable = true;
      git = true;
      icons = "auto";
    };
    bat.enable = true;
    ripgrep.enable = true;
    fzf = {
      enable = true;
      defaultCommand = "fd --type f";
      changeDirWidgetCommand = "fd --type d";
      colors = {
        fg = "#ebdbb2";
        bg = "#282828";
        hl = "#fabd2f";
        "fg+" = "#ebdbb2";
        "bg+" = "#3c3836";
        "hl+" = "#fabd2f";
        info = "#83a598";
        prompt = "#bdae93";
        spinner = "#fabd2f";
        pointer = "#83a598";
        marker = "#fe8019";
        header = "#665c54";
      };
    };

    # Git tools
    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user.name = "Ammar Nanjiani";
        user.email = "ammar.nanjiani@gmail.com";
        init.defaultBranch = "main";
        credential.helper = "store";
        pull.rebase = false;
        push.autoSetupRemote = true;
        safe.directory = "/mnt/nfs/persona-mcp";
      };
    };
    lazygit.enable = true;

    # Navigation
    zoxide = {
      enable = true;
      options = [ "--cmd cd" ];
    };
  };
}
