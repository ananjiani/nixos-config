{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    # inputs.opencode.packages.${pkgs.system}.default
    gh
    pgadmin4-desktopmode
    # inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs # Temporarily disabled - hash mismatch
  ];

  programs = {
    opencode.enable = true;
    jujutsu = {
      enable = true;
      settings = {
        user = {
          email = "ammar.nanjiani@gmail.com";
          name = "Ammar Nanjiani";
        };
      };
    };
  };
}
