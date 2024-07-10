{ config, lib, pkgs, ... }:

{
  home.sessionPath = [ "$HOME/.local/bin" ];
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        set -g fish_key_bindings fish_vi_key_bindings
        bind -M insert \cf forward-char
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
