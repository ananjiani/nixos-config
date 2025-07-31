{
  pkgs,
  ...
}:

{
  home.shellAliases = {
    lf = "lfcd";
  };

  programs = {
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

      commands = {
        ripdrag-out = ''%${pkgs.ripdrag}/bin/ripdrag -a -x "$fx"'';
        mkdir = ''
          ''${{
                  printf "Directory Name: "
                  read DIR
                  mkdir $DIR
                }}'';
        extract = ''
          ''${{
            set -f
            atool -x $f
          }}'';
        on-cd = ''
          ''${{
              fmt="$(starship prompt)"
              lf -remote "send $id set promptfmt \"$fmt\""
          }}'';
      };

      keybindings = {
        # "\\\"" = "";
        # "`" = "mark-load";
        # "\\'" = "mark-load";
        "<enter>" = "open";
        z = "extract";
        o = "ripdrag-out";
        "g~" = "cd";
        "gr" = "cd /";
        "go" = "cd ~/Documents/org";
        "gd" = "cd ~/Downloads";
        "gD" = "cd ~/Documents";
        "gp" = "cd ~/Documents/projects";
        "g." = "cd ~/.dotfiles";
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

    fish = {
      plugins = [
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

      functions.lfcd = {
        body = ''
          cd "$(command lf -print-last-dir $argv)"
        '';
      };
    };
  };
}
