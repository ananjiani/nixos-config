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

  home.shellAliases = {
    ecc = "emacsclient -c";
    ec = "emacsclient";
    ecn = "emacsclient -nw";
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

  home.packages = with pkgs; [
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

  home.sessionVariables = {
    DOOMDIR = doom-dir;
  };

  # doom dependencies

  home.activation.installDoomEmacs = lib.hm.dag.entryAfter [ "installPackages" ] ''
    if [ ! -d "$HOME/.emacs.d" ]; then
      PATH="${config.home.path}/bin:$PATH"
      git clone --depth=1 --single-branch https://github.com/doomemacs/doomemacs $HOME/.emacs.d
    fi
  '';

  home.activation.decryptEmacs = lib.hm.dag.entryAfter [ "installDoomEmacs" ] ''
    PATH="${config.home.path}/bin:$PATH"
    sops -d ~/.dotfiles/secrets/emacs/emacs.sops > ~/.dotfiles/secrets/emacs/emacs
    sops -d ~/.dotfiles/secrets/emacs/emacs.pub.sops > ~/.dotfiles/secrets/emacs/emacs.pub
  '';
  home.activation.doomSync = lib.hm.dag.entryAfter [ "decryptEmacs" ] ''
    PATH="${config.home.path}/bin:$PATH"
    export DOOMDIR=${doom-dir}
    $HOME/.emacs.d/bin/doom sync
  '';

  home.sessionPath = [ "$HOME/.emacs.d/bin" ];
}
