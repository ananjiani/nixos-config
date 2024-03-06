{ config, pkgs, lib, ... }:

{

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
    font-awesome
    hack-font
    emacs-all-the-icons-fonts
  ];

}
