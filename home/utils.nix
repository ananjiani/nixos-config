{ config, pkgs, lib, nix-colors, ...}:

{

  imports = [
    ./cli-tools.nix
  ];

  home.shellAliases = {
    ls = "eza -a";
    lf = "lfcd";
    lg = "lazygit";
  };

  programs = {
    bash.enable = true;
    
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        set -g fish_key_bindings fish_vi_key_bindings
      '';
      plugins = with pkgs.fishPlugins; [
        {
          name = "fish-lf-icons";
          src = pkgs.fetchFromGitHub {
            owner = "joshmedeski";
            repo = "fish-lf-icons";
            rev = "d1c47b2088e0ffd95766b61d2455514274865b4f";
            sha256 = "6po/PYvq4t0K8Jq5/t5hXPLn80iyl3Ymx2Whme/20kc=";
          };
        }
      ];
      functions = 
      {
        lfcd = {
          body = ''
          cd "$(command lf -print-last-dir $argv)"
          '';
        };
      };
    };

    starship.enable = true;    
    eza = {
      enable = true;
      git = true;
      icons = true;
    };
    nushell.enable = true;

    fzf = {
      enable = true;
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

    bat.enable = true;

    zellij = {
      enable = true;
      settings = {
        theme = "gruvbox-dark";
        default_shell = "fish";
      };
    };

    foot = {
      enable = true;
      settings = {
        main = {
          shell = "${pkgs.zellij}/bin/zellij";
          term = "xterm-256color";
          font = "hack:size=14";
        };
        
        colors = {
          background = "282828";
          foreground = "ebdbb2";
          regular0 = "282828";
          regular1 = "cc241d";
          regular2 = "98971a";
          regular3 = "d79921";
          regular4 = "458588";
          regular5 = "b16286";
          regular6 = "689d6a";
          regular7 = "a89984";
          bright0 = "928374";
          bright1 = "fb4934";
          bright2 = "b8bb26";
          bright3 = "fabd2f";
          bright4 = "83a598";
          bright5 = "d3869b";
          bright6 = "8ec07c";
          bright7 = "ebdbb2";
        };
      };
    };

    git = {
      enable = true;
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
        credential.helper = "store";
      };
    };
    lazygit.enable = true;

    vscode = {
      enable = true;
      package = pkgs.vscode.fhs;
      extensions = with pkgs.vscode-marketplace; [
          usernamehw.errorlens
          sainnhe.gruvbox-material
          jonathanharty.gruvbox-material-icon-theme
          bbenoist.nix
          arrterian.nix-env-selector
          charliermarsh.ruff
          vscodevim.vim
          ms-python.python
          ms-python.mypy-type-checker
          ms-python.vscode-pylance
          tamasfe.even-better-toml
        ];
    };

    lf = {
      enable = true;
      settings = {
        preview = true;
        hidden = true;
        number = true;
        drawbox = true;
        icons = true;
        ignorecase = true;
        relativenumber = true;
        sixel = true;
      };

      commands  = {
        ripdrag-out = ''%${pkgs.ripdrag}/bin/ripdrag -a -x "$fx"'';
        editor-open = ''$$EDITOR $f'';
        mkdir = ''
        ''${{
          printf "Directory Name: "
          read DIR
          mkdir $DIR
        }}
        '';
      };

      keybindings = {
        # "\\\"" = "";
        # "`" = "mark-load";
        # "\\'" = "mark-load";
        "<enter>" = "open";

        do = "ripdrag-out";
        e = "editor-open";
        "g~" = "cd";
        "gr" = "cd /";
        "go" = "cd ~/Documents/org";
        "gd" = "cd ~/Downloads";
        "gD" = "cd ~/Documents";
        "gp" = "cd ~/Documents/projects";

        V = ''''$${pkgs.bat}/bin/bat --paging=always --theme=gruvbox "$f"'';
      };

      previewer = {
        keybinding = "i";
        source = "${pkgs.ctpv}/bin/ctpv";
      };

      extraConfig = ''
        &${pkgs.ctpv}/bin/ctpv -s $id
        cmd on-quit %${pkgs.ctpv}/bin/ctpv -e $id
        set cleaner ${pkgs.ctpv}/bin/ctpvclear
      '';

    };
  };

  home.packages = with pkgs; [
      inkscape
      xfce.thunar
      xfce.thunar-archive-plugin
      xfce.thunar-media-tags-plugin
  ];

  home.file = {
    # ".config/Thunar/accels.scm".source = ./config/thunar/accels.scm;
    ".config/Thunar/uca.xml".source = ./config/thunar/uca.xml;
  };
}
