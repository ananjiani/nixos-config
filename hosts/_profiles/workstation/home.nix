{
  lib,
  ...
}:

{
  imports = [
    # Import all essentials first
    ../essentials/home.nix

    # Workstation-specific additions
    ../../../modules/home/config/defaults-workstation.nix
    ../../../modules/home/gaming.nix
    # ../../../modules/home/editors/lvim.nix
    #../../../modules/home/editors/vscode.nix
    ../../../modules/home/firefox.nix
    ../../../modules/home/wm/wm.nix
    ../../../modules/home/writing.nix
    ../../../modules/home/programs.nix
    ../../../modules/home/config/wallpaper.nix
    ../../../modules/home/terminal/gui-integration.nix
    ../../../modules/home/terminal/emulator/foot.nix
    ../../../modules/home/terminal/emulator/ghostty.nix
    ../../../modules/home/terminal/programs/lf.nix
    ../../../modules/home/terminal/programs/atuin.nix
    # ../../../modules/home/terminal/programs/iamb.nix
    ../../../modules/home/dev/lang/python.nix
    ../../../modules/home/dev/lang/nixlang.nix
    ../../../modules/home/dev/nix-direnv.nix
    ../../../modules/home/dev/programs.nix
    ../../../modules/home/dev/claude-code.nix
  ];

  # Doom Emacs via dendritic module
  doom-emacs = {
    enable = lib.mkDefault true;
    variant = "pgtk";
    service.enable = true;
    secrets.enable = true;
  };

  # Default wallpaper configuration
  wallpaper = {
    enable = lib.mkDefault true;
    path = lib.mkDefault ./wallpapers/revachol.jpg;
    mode = lib.mkDefault "fill";
  };

  # Note: programs.home-manager.enable is already set in essentials
}
