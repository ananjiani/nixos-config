{ config, pkgs, lib, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs29;
  };

  services.emacs.enable = true;
  
  home.sessionVariables = {
    DOOMDIR = "$HOME/.dotfiles/home/emacs/doom-emacs";
  };

  home.activation.installDoomEmacs = lib.hm.dag.entryAfter ["installPackages"] ''
      if [ ! -d "$HOME/.emacs.d" ]; then
        PATH="${config.home.path}/bin:$PATH"
        git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
        $HOME/.emacs.d/bin/doom sync
        $HOME/.emacs.d/bin/doom env
      fi
    '';

  home.activation.doomSync = lib.hm.dag.entryAfter ["installDoomEmacs"] ''
      PATH="${config.home.path}/bin:$PATH"
      $HOME/.emacs.d/bin/doom sync -e
    '';

  home.sessionPath = [
    "$HOME/.emacs.d/bin"
  ];
}