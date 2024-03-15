{ config, lib, pkgs, ... }:

{

  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
    extensions = with pkgs.vscode-marketplace; [
      usernamehw.errorlens
      sainnhe.gruvbox-material
      jonathanharty.gruvbox-material-icon-theme
      bbenoist.nix
      arrterian.nix-env-selector
      charliermarsh.ruff
      ms-python.python
      ms-python.mypy-type-checker
      ms-python.vscode-pylance
      tamasfe.even-better-toml
      vscodevim.vim
    ];
  };
}
