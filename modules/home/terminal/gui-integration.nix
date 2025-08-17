# Desktop-only terminal additions
{
  pkgs,
  ...
}:

{
  # Desktop-specific aliases
  home.shellAliases = {
    rd = "ripdrag";
    frd = "ripdrag $(fzf)";
    fo = "open $(fzf)"; # Open with desktop app
    fc = "emacsclient $(fzf)"; # Emacs client
  };

  programs = {
    # Additional shell for desktop experimentation
    nushell = {
      enable = true;
      package = pkgs.nushell;
    };

    # Desktop-specific fish configuration for Emacs vterm
    fish = {
      interactiveShellInit = ''
        # Emacs vterm integration
        if set -q INSIDE_EMACS
            # Use default (emacs-style) keybindings when inside Emacs
            set -g fish_key_bindings fish_default_key_bindings
        end
        functions --copy fish_prompt vterm_old_fish_prompt
      '';
      functions = {
        # Emacs vterm specific functions
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
      };
    };
  };

  # Desktop-only packages
  home.packages = with pkgs; [
    ripdrag # GUI drag & drop
    chafa # Terminal image viewer
  ];
}
