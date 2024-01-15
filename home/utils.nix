{ config, pkgs, lib, nix-colors, ...}:

{
  programs = {
    bash.enable = true;

    git = {
      enable = true;
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
      };
    };

    vscode = {
      enable = true;   
    };

    lf = {
      enable = true;
      settings = {
        hidden = true;
        number = true;
        relativenumber = true;
      };
    };
  };

  home.packages = with pkgs; [
      inkscape
      xfce.thunar
      xfce.thunar-archive-plugin
      xfce.thunar-media-tags-plugin
  ];

  home.file = {
    # ".config/Thunar/accels.scm".source = ./config/thunar/accels.scm;
    ".config/Thunar/uca.xml".source = ./config/thunar/uca.xml;
  };
}
