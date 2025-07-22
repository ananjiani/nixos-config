{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [ claude-code ];
  # Create stable binary path
  home.activation.claudeStableLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p $HOME/.local/bin
    rm -f $HOME/.local/bin/claude
    ln -s ${pkgs.claude-code}/bin/claude $HOME/.local/bin/claude
  '';

  # Add to PATH
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Preserve config during switches
  home.activation.preserveClaudeConfig = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    [ -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json" "$HOME/.claude.json.backup" || true
  '';

  home.activation.restoreClaudeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    [ -f "$HOME/.claude.json.backup" ] && [ ! -f "$HOME/.claude.json" ] && cp -p "$HOME/.claude.json.backup" "$HOME/.claude.json" || true
  '';
}
