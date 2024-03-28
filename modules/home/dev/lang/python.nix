{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    nodePackages.pyright
    python311Packages.python-lsp-server
    ruff-lsp
  ];
}
