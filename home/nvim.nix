{
  config,
  pkgs,
  lib,
  nixvim,
  ...
}: {
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

    options = {
      number = true;
      relativenumber = true;
      signcolumn = "number";
    };

    clipboard = {
      providers.wl-copy.enable = true;
      register = "unnamedplus";
    };

    plugins = {
      nix.enable = true;
      undotree.enable = true;
      harpoon.enable = true;
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
      lsp-format.enable = true;
      lspkind.enable = true;
      dap = {
        enable = true;
        extensions = {
          dap-python.enable = true;
          dap-ui.enable = true;
        };
      };
      none-ls = {
        enable = true;
        enableLspFormat = true;
        sources = {
          code_actions = {
            statix.enable = true;
          };
          diagnostics = {
            mypy.enable = true;
          };
          formatting = {
            alejandra.enable = true;
          };
        };
      };
      lsp = {
        enable = true;
        servers = {
          pyright.enable = true;
          ruff-lsp.enable = true;
          nil_ls.enable = true;
          nushell.enable = true;
          yamlls.enable = true;
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
