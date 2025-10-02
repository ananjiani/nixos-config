{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    # inputs.opencode.packages.${pkgs.system}.default
    aider-chat
    gh
    pgadmin4-desktopmode
    # inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs # Temporarily disabled - hash mismatch
  ];

  programs = {
    codex = {
      enable = true;
    };
    # opencode = {
    #   enable = true;
    # };
  };
}
