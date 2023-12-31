{ config, pkgs, lib, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs29;
  };

  services.emacs.enable = true;

  home.activation.installDoomEmacs = lib.hm.dag.entryAfter ["installPackages"] ''
      if [ ! -d "$HOME/.emacs.d" ]; then
        PATH="${config.home.path}/bin:$PATH"
        git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
        mkdir $HOME/.doom.d
        cp $HOME/.emacs.d/templates/init.example.el $HOME/.doom.d/init.el
        cp $HOME/.emacs.d/templates/config.example.el $HOME/.doom.d/config.el
        cp $HOME/.emacs.d/templates/packages.example.el $HOME/.doom.d/packages.el
        $HOME/.emacs.d/bin/doom sync
        $HOME/.emacs.d/bin/doom env
      fi
    '';

  home.activation.doomSync = lib.hm.dag.entryAfter ["installDoomEmacs"] ''
      PATH="${config.home.path}/bin:$PATH"
      $HOME/.emacs.d/bin/doom sync -e
    '';

  home.file = {
    ".doom.d/config.el".source = ../doom-emacs/config.el;
    ".doom.d/packages.el".source = ../doom-emacs/packages.el;
    ".doom.d/init.el".source = ../doom-emacs/init.el;
  };

  home.sessionPath = [
    "$HOME/.emacs.d/bin"
  ];
}