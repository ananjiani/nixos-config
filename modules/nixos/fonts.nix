{ config, pkgs, lib, ... }:

{

  fonts.packages = with pkgs; [
    #(nerdfonts.override { fonts = [ "FiraCode" ]; })
    nerd-fonts.fira-code
    font-awesome
    hack-font
    emacs-all-the-icons-fonts
    liberation_ttf
    inter
  ];

}
