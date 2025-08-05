# Essential configuration - the absolute minimum everyone needs
{
  lib,
  ...
}:

{
  imports = [
    # Core terminal tools (shells, git, file navigation)
    ../../../modules/home/terminal/core.nix

    # Basic configuration defaults
    ../../../modules/home/config/defaults.nix

    # SOPS for secrets management
    ../../../modules/home/config/sops.nix
  ];

  # Basic home-manager configuration
  home = {
    username = "ammar";
    homeDirectory = "/home/ammar";
    stateVersion = "24.05";
  };

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  # Essential environment variables
  home.sessionVariables = {
    EDITOR = lib.mkDefault "vim";
  };
}
