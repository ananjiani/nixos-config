{
  pkgs,
  ...
}:
{

  programs.helix = {
    enable = true;

    languages.language = [
      {
        name = "nix";
        formatter.command = "nixpkgs-fmt";
      }
      {
        name = "python";
        roots = [ "pyproject.toml" ];
        language-servers = [
          "pyright"
          "ruff"
        ];
      }
    ];

    languages.language-server = {
      pyright = {
        command = "pyright-langserver";
        args = [ "--stdio" ];
      };
      ruff = {
        command = "ruff-lsp";
        config.settings.run = "onSave";
      };
    };
    settings = {
      theme = "gruvbox_dark_hard";
      editor = {
        line-number = "relative";
        auto-save = true;
        bufferline = "multiple";
        cursorline = true;
        rulers = [ 120 ];
        true-color = true;
        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
        indent-guides.render = true;
        lsp = {
          display-messages = true;
        };
        statusline.left = [
          "mode"
          "spinner"
          "version-control"
          "file-name"
        ];
      };
      keys.normal = {
        esc = [
          "collapse_selection"
          "keep_primary_selection"
        ];
      };
    };

    extraPackages = with pkgs; [
      nil
      nixpkgs-fmt
      nodePackages.pyright
      nodePackages.vscode-json-languageserver
      taplo
      taplo-cli
      taplo-lsp
      ruff
      ruff-lsp
      yaml-language-server
    ];
  };
}
