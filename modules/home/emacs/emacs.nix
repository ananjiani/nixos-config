{ config, pkgs, lib, ... }:
let doom-dir = "$HOME/.dotfiles/modules/home/emacs/doom-emacs";
in {

  home.shellAliases = {
    ecc = "emacsclient -c";
    ec = "emacsclient";
    ecn = "emacsclient -nw";
  };

  programs = {
    emacs = {
      enable = true;
      package = pkgs.emacs29;
      extraPackages = epkgs: [ epkgs.vterm ];
    };
    #mu.enable = true;
  };

  services.emacs = {
    enable = true;
    package = pkgs.emacs29;
  };

  home.packages = with pkgs; [ gzip fd ripgrep nixfmt ];

  home.sessionVariables = { DOOMDIR = doom-dir; };

  # doom dependencies

  home.activation.installDoomEmacs =
    lib.hm.dag.entryAfter [ "installPackages" ] ''
      if [ ! -d "$HOME/.emacs.d" ]; then
        PATH="${config.home.path}/bin:$PATH"
        git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
      fi
    '';

  home.activation.doomSync = lib.hm.dag.entryAfter [ "installDoomEmacs" ] ''
    PATH="${config.home.path}/bin:$PATH"
    export DOOMDIR=${doom-dir}
    $HOME/.emacs.d/bin/doom sync
  '';

  home.sessionPath = [ "$HOME/.emacs.d/bin" ];
}
