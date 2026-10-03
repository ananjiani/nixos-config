# Steam Deck — Home Manager configuration
#
# Minimal user config. Save sync (Syncthing, Ludusavi) and MangoHUD come from
# the dendritic gaming module. `desktop = false` drops its launcher extras
# (Hydra, Heroic, Lutris, UMU, protontricks, winetricks, Vesktop), because
# Jovian already provides Steam, gamescope, the controller stack and MangoHUD.
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
    # Jovian already provides Steam, gamescope, controller udev rules and
    # MangoHUD. This drops Hydra and the other desktop launcher extras.
    desktop = false;
    syncthing.enable = true;
    ludusavi.backupPath = "/home/ammar/Games/Saves/steamdeck";
  };

  # Note: programs.home-manager.enable is already set in essentials
}
