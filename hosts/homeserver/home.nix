{
  ...
}:

{
  imports = [
    # Core terminal configuration (shells, CLI tools, etc.)
    ../../modules/home/terminal/core.nix

    # System monitoring tools
    ../../modules/home/terminal/monitoring.nix

    # SOPS disabled for initial deployment
    # ../../modules/home/config/sops.nix
  ];

  # Basic home-manager configuration for server
  home = {
    username = "ammar";
    homeDirectory = "/home/ammar";
    stateVersion = "24.05";
  };

  programs = {
    home-manager.enable = true;
  };

  home.sessionVariables = {
    EDITOR = "vim";
  };
}
