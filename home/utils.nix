{ config, pkgs, lib, nix-colors, ...}:

{
  programs = {
    bash.enable = true;

    tmux = {
      enable = true;
      keyMode = "vi";
    };

    git = {
      enable = true;
      userName = "Ammar Nanjiani";
      userEmail = "ammar.nanjiani@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
        credential.helper = "store";
      };
    };

    vscode = {
      enable = true;
      package = pkgs.vscode.fhs;
      extensions = with pkgs.vscode-marketplace; [
          usernamehw.errorlens
          sainnhe.gruvbox-material
          jonathanharty.gruvbox-material-icon-theme
          bbenoist.nix
          arrterian.nix-env-selector
          charliermarsh.ruff
          vscodevim.vim
          ms-python.python
          ms-python.mypy-type-checker
          ms-python.vscode-pylance
          tamasfe.even-better-toml
        ];
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
