{ config, pkgs, lib, ... }: {

  home.packages = with pkgs; [ 
    nil
    nodePackages.pyright
    python311Packages.python-lsp-server
  ];

}
