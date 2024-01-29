{ config, pkgs, lib, nixvim, ...}:


{
  imports = [
    nixvim.homeManagerModules.nixvim
  ];

  home.shellAliases = {
    vi = "nvim";
    vim = "nvim";
    vimdiff = "nvim -d";
  };

  programs.nixvim = {
    enable = true;
    colorschemes.gruvbox = {
      enable = true;
    };

    clipboard = {
      providers.wl-copy.enable = true;
      register = "unnamedplus";
    };

    plugins = {
      treesitter = {
      	enable = true;
	indent = true;
	nixvimInjections = true;
      };
      telescope.enable = true;
      # codeium = {
      # 	enable = true;
      #   wrapper = "";
      # };
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = true;
        };
      };
    };
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
