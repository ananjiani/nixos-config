{ config, pkgs, pkgs-stable, lib, ... }:

let
  tex = (pkgs.texlive.combine {
    inherit (pkgs.texlive)
      scheme-medium dvisvgm dvipng # for preview and export as html
      wrapfig amsmath ulem hyperref capt-of biblatex biber biblatex-chicago
      footmisc ragged2e titlesec geometry xcolor;
    #(setq org-latex-compiler "lualatex")
    #(setq org-preview-latex-default-process 'dvisvgm)
  });
in {
  home.packages = (with pkgs; [
    tex
    xcolor
    inkscape
    pinta
    vlc
    xfce.thunar
    xfce.thunar-archive-plugin
    xfce.thunar-media-tags-plugin
    obs-studio
    gst_all_1.gstreamer
    obs-studio-plugins.obs-gstreamer
    obs-studio-plugins.obs-vkcapture
    libva-utils
    cmatrix
    ungoogled-chromium
    element-desktop
    xournalpp
  ])

    ++ (with pkgs-stable; [ zotero ]);
}
