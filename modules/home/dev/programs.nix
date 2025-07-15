{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  home.packages = with pkgs; [
    claude-code
    opencode
    aider-chat
    gh
    pgadmin4-desktopmode
    inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs
  ];
}
