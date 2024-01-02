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
      userSettings = {
        "window.titleBarStyle" = "custom";
      };
    };
  };
}
