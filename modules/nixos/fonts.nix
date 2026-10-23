{
  pkgs,
  ...
}:

{

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    font-awesome
    hack-font
    emacs-all-the-icons-fonts
    liberation_ttf
    carlito # metric-compatible Calibri
    caladea # metric-compatible Cambria
    inter
    ia-writer-duospace
    etBook
    alegreya
    noto-fonts-cjk-sans
  ];

}
