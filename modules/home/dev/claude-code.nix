{
  lib,
  pkgs,
  ...
}:

let
  claude-code-acp = pkgs.buildNpmPackage rec {
    pname = "claude-code-acp";
    version = "0.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "zed-industries";
      repo = "claude-code-acp";
      rev = "refs/heads/main";
      hash = "sha256-m6DLqPMCzOj7/D3dkc+XFOy3iqZq4wRm8M200RKjfSA=";
    };

    npmDepsHash = "sha256-OX/LukdQFqltWmBO5Ta6N33yT2fuc66cE1cWMkq/8p0=";

    npmBuildScript = "build";
  };
in
{
  home = {
    packages = with pkgs; [
      claude-code
      claude-code-acp
    ];

    sessionPath = [ "$HOME/.local/bin" ];

    activation = {
      # Create stable binary path
      claudeStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p $HOME/.local/bin
        rm -f $HOME/.local/bin/claude
        ln -s ${pkgs.claude-code}/bin/claude $HOME/.local/bin/claude
      '';

      # Preserve config during switches
      preserveClaudeConfig = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
      '';

      restoreClaudeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
      '';
    };
  };
}
