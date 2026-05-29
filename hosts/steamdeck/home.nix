# Steam Deck — Home Manager configuration
#
# Minimal user config. Gaming tools (Ludusavi, Syncthing, MangoHUD, Vesktop,
# Heroic, UMU, protontricks, Hydra) come from the dendritic gaming module.
{
  ...
}:

{
  imports = [
    ../_profiles/essentials/home.nix
  ];

  # ── Gaming user-level tools ────────────────────────────────────────
  gaming = {
    enable = true;
    syncthing.enable = true;
    ludusavi.backupPath = "/home/ammar/Games/Saves/steamdeck";
  };

  # Note: programs.home-manager.enable is already set in essentials
}
