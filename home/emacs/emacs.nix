{ config, pkgs, lib, ... }:

let
  doom-dir = "$HOME/.dotfiles/home/emacs/doom-emacs";
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs29;
  };

  #services.emacs.enable = true;
  
  home.sessionVariables = {
    DOOMDIR = doom-dir;
  };

  # doom dependencies
  home.packages = with pkgs; [
        gzip
        fd
        ripgrep
    ];

  home.activation.installDoomEmacs = lib.hm.dag.entryAfter ["installPackages"] ''
      if [ ! -d "$HOME/.emacs.d" ]; then
        PATH="${config.home.path}/bin:$PATH"
        git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
      fi
    '';

  home.activation.doomSync = lib.hm.dag.entryAfter ["installDoomEmacs"] ''
      PATH="${config.home.path}/bin:$PATH"
      export DOOMDIR=${doom-dir}
      $HOME/.emacs.d/bin/doom sync
    '';

  home.sessionPath = [
    "$HOME/.emacs.d/bin"
  ];
}