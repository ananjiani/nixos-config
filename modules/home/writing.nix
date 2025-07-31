{
  lib,
  pkgs,
  pkgs-stable,
  ...
}:

let
  tex = pkgs.texlive.combine {
    inherit (pkgs.texlive)
      scheme-medium
      dvisvgm
      dvipng # for preview and export as html
      wrapfig
      amsmath
      ulem
      hyperref
      capt-of
      biblatex
      biber
      biblatex-chicago
      footmisc
      ragged2e
      titlesec
      geometry
      xcolor
      ;
    #(setq org-latex-compiler "lualatex")
    #(setq org-preview-latex-default-process 'dvisvgm)
  };
in
{
  home = {
    packages =
      (with pkgs; [
        tex
        vale
        vale-ls
      ])
      ++ (with pkgs-stable; [ zotero ]);

    file = {
      ".config/vale/.vale.ini".source = ./.vale.ini;
    };

    activation.valeSync = lib.hm.dag.entryAfter [ "installPackages" ] ''
      vale sync
    '';
  };
}
