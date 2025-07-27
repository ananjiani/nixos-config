{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  home.packages = with pkgs; [
    # inputs.opencode.packages.${pkgs.system}.default
    aider-chat
    gh
    pgadmin4-desktopmode
    inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs
  ];
}
