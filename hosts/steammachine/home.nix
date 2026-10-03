# Steam Machine — Home Manager configuration
#
# Minimal user config. Save sync (Syncthing, Ludusavi) and MangoHUD come from
# the dendritic gaming module, wired in through flake.nix. `desktop = false`
# drops its launcher extras, because Jovian already provides Steam, gamescope,
# the controller stack and MangoHUD.
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
    # MangoHUD, so skip the desktop launcher half: Hydra, Heroic, Lutris,
    # BoilR, protonup-qt, Vesktop and the capture tools.
    desktop = false;
    syncthing.enable = true;
    ludusavi.backupPath = "/home/ammar/Games/Saves/steammachine";
  };
}
