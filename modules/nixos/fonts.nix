{
  config,
  pkgs,
  lib,
  ...
}:

{

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    font-awesome
    hack-font
    emacs-all-the-icons-fonts
    liberation_ttf
    inter
    ia-writer-duospace
  ];

}
