{
  pkgs,
  pkgs-stable,
  ...
}:

{
  home.sessionPath = [ "$HOME/.local/bin" ];
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        if set -q INSIDE_EMACS
            # Use default (emacs-style) keybindings when inside Emacs
            set -g fish_key_bindings fish_default_key_bindings
        else
            # Use vi keybindings in regular terminals
            set -g fish_key_bindings fish_vi_key_bindings
            bind -M insert \cf forward-char
        end
        set -g fish_key_bindings fish_vi_key_bindings
        bind -M insert \cf forward-char
        functions --copy fish_prompt vterm_old_fish_prompt
      '';
      # plugins = with pkgs.fishPlugins; [ ];
      functions = {
        vterm_printf = ''
          if begin; [  -n "$TMUX" ]  ; and  string match -q -r "screen|tmux" "$TERM"; end
              # tell tmux to pass the escape sequences through
              printf "\ePtmux;\e\e]%s\007\e\\" "$argv"
          else if string match -q -- "screen*" "$TERM"
              # GNU screen (screen, screen-256color, screen-256color-bce)
              printf "\eP\e]%s\007\e\\" "$argv"
          else
              printf "\e]%s\e\\" "$argv"
        '';
        vterm_prompt_end = "vterm_printf '51;A'(whoami)'@'(hostname)':'(pwd)";
        fish_prompt = ''
          --description 'Write out the prompt; do not replace this. Instead, put this at end of your file.'
              # Remove the trailing newline from the original prompt. This is done
              # using the string builtin from fish, but to make sure any escape codes
              # are correctly interpreted, use %b for printf.
              printf "%b" (string join "\n" (vterm_old_fish_prompt))
              vterm_prompt_end
        '';
        fish_title = ''
          hostname
          echo ":"
          prompt_pwd
        '';
      };
    };

    bash.enable = true;

    nushell = {
      enable = true;
      package = pkgs.nushell;
    };

    starship = {
      enable = true;
      settings = {
        add_newline = false;
        line_break.disabled = true;
      };
      package = pkgs-stable.starship;
    };
    zellij = {
      enable = true;
      settings = {
        theme = "gruvbox-dark";
        default_shell = "fish";
        pane_frames = false;
        on_force_close = "quit";
      };
    };

  };
}
