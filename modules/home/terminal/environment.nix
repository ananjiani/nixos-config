{ config, lib, pkgs, ... }:

{
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
      package = pkgs.nushellFull;
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
        copy_on_select = false;
        pane_frames = false;
        on_force_close = "quit";
      };
    };
    atuin = {
      enable = true;
      settings = { keymap_mode = "vim-normal"; };
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
  };
}
