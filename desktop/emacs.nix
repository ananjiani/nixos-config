{ config, pkgs, lib, ... }:

let

in
{
  home.packages = with pkgs; [
    ((emacsPackagesFor emacs-pgtk).emacsWithPackages (
      epkgs: [
        epkgs.org-roam
      ]
    ))
  ]

  home.activation.installDoomEmacs =  ''
    if [ ! -d "$XDG_CONFIG_HOME/emacs" ]; then
      git clone --depth=1 "https://github.com/doomemacs/doomemacs" "$XDG_CONFIG_HOME/emacs"
      $XDG_CONFIG_HOME/emacs/bin/doom install
      export PATH=$XDG_CONFIG_HOME/emacs/bin:$PATH
  '';
}