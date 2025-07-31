{
  config,
  pkgs,
  lib,
  ...
}:
let
  doom-dir = "$HOME/.dotfiles/modules/home/editors/doom-emacs";
in
{
  home = {
    shellAliases = {
      ecc = "emacsclient -c";
      ec = "emacsclient";
      ecn = "emacsclient -nw";
    };

    packages = with pkgs; [
      xclip
      gzip
      fd
      ripgrep
      nodejs
      nodePackages.prettier
      findutils
      nodePackages.vscode-json-languageserver
      (aspellWithDicts (
        dicts: with dicts; [
          en
          en-computers
          en-science
        ]
      ))
    ];

    sessionVariables = {
      DOOMDIR = doom-dir;
    };

    sessionPath = [ "$HOME/.emacs.d/bin" ];

    activation = {
      installDoomEmacs = lib.hm.dag.entryAfter [ "installPackages" ] ''
        if [ ! -d "$HOME/.emacs.d" ]; then
          PATH="${config.home.path}/bin:$PATH"
          git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
        fi
      '';

      decryptEmacs = lib.hm.dag.entryAfter [ "installDoomEmacs" ] ''
        PATH="${config.home.path}/bin:$PATH"
        sops -d ~/.dotfiles/secrets/emacs/emacs.sops > ~/.dotfiles/secrets/emacs/emacs
        sops -d ~/.dotfiles/secrets/emacs/emacs.pub.sops > ~/.dotfiles/secrets/emacs/emacs.pub
      '';

      doomSync = lib.hm.dag.entryAfter [ "decryptEmacs" ] ''
        PATH="${config.home.path}/bin:$PATH"
        export DOOMDIR=${doom-dir}
        $HOME/.emacs.d/bin/doom sync
      '';
    };
  };

  programs = {
    emacs = {
      enable = true;
      package = pkgs.emacs-pgtk;
      extraPackages = epkgs: [ epkgs.vterm ];
    };
    #mu.enable = true;
  };

  services.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
  };
}
