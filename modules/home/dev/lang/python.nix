{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    python311Full
    nodePackages.pyright
    python311Packages.python-lsp-server
    ruff
    ruff-lsp
    python311Packages.debugpy
  ];
}
