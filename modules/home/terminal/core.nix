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
    };

    packages =
      (with pkgs; [
        # Archive tools
        atool
        unrar
        p7zip

        # Media tools
        ffmpeg
        ffmpegthumbnailer

        # Security tools
        gnupg
        pinentry
        rage

        # Text processing
        jq
        pandoc
        poppler_utils

        # System tools
        tealdeer
        du-dust
        duf
        ripgrep-all
        fd
        sshfs
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
      };
    };

    # Prompt
    starship = {
      enable = true;
      settings = {
        add_newline = false;
        line_break.disabled = true;
      }
      // (
        if builtins.getEnv "INSIDE_EMACS" != "" then
          {
            # Override symbols only when inside Emacs
            git_branch.symbol = " ";
            directory.read_only = " [RO]";
            git_status = {
              modified = "M";
              staged = "S";
              untracked = "U";
              ahead = "↑";
              behind = "↓";
            };
          }
        else
          { }
      );
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
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
        credential.helper = "store";
        pull.rebase = false;
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
