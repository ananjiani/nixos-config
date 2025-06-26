{
  config,
  pkgs,
  lib,
  ...
}:

let
  wallpaper = ./wallpapers/revachol.jpg;
in
{
  imports = [
    ../../modules/home/gaming.nix
    ../../modules/home/editors/emacs.nix
    # ../../modules/home/editors/lvim.nix
    #../../modules/home/editors/vscode.nix
    ../../modules/home/wm/wm.nix
    ../../modules/home/writing.nix
    ../../modules/home/programs.nix
    ../../modules/home/config/defaults.nix
    ../../modules/home/config/sops.nix
    ../../modules/home/terminal/environment.nix
    ../../modules/home/terminal/cli-tools.nix
    ../../modules/home/terminal/emulator/foot.nix
    ../../modules/home/terminal/programs/lf.nix
    ../../modules/home/terminal/programs/atuin.nix
    # ../../modules/home/terminal/programs/iamb.nix
    ../../modules/home/dev/lang/python.nix
    ../../modules/home/dev/lang/nixlang.nix
    ../../modules/home/dev/nix-direnv.nix
    ../../modules/home/dev/programs.nix
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "ammar";
  home.homeDirectory = "/home/ammar";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
