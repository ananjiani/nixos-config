{ config, pkgs, lib, ...}:

let
  nixvim = import (builtins.fetchGit {
    url = "https://github.com/nix-community/nixvim";
  });
in
{
  imports = [
    nixvim.homeManagerModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
  };
  # programs = {
  #   nvim = let 
  #     toLua = str: "lua << EOF\n${str}\nEOF\n"; 
  #     toLuaFile = file: "lua << EOF\n${builtins.readFile file}\nEOF\n";
  #   in {
  #     enable = true;

  #     viAlias = true;
  #     vimAlias = true;
  #     vimdiffAlias = true;
  #     defaultEditor = true;

  #     plugins = with pkgs.vimPlugins; [
        
  #     ];
  #   };
  # };
}