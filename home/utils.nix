{ config, pkgs, lib, nix-colors, ...}:

{
  programs = {
    bash.enable = true;

    git = {
      enable = true;
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
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
  ];
}