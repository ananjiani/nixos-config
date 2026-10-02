# Steam Machine: Stock SteamOS Now, Jovian NixOS Later

**Date**: 2026-09-29
**Status**: Deferred — keep the working stock SteamOS install for now

## Summary

Use the Steam Machine on stock SteamOS now. Copy finished games from the desktop or theoden to its local SSD. Add them as normal non-Steam games. Sync only their save folders.

Keep the full Jovian NixOS replacement as a later project. Do not add Hydra, SteamTools, LuaTools, Millennium, SLSsteam, or a custom Steam shortcut writer to the Steam Machine.

## Decisions

- Keep stock SteamOS while it works.
- Keep Hydra on `ammars-pc` only.
- Keep theoden as the archive at `/mnt/storage/games/library`.
- Copy games to the Steam Machine SSD before play.
- Sync save folders, not game folders or complete Proton prefixes.
- Use Home Manager on SteamOS only for user packages and user services.
- Replace SteamOS only when the extra system control is worth the install risk.
- When the switch happens, use KDE Plasma and the Steam Machine-specific Jovian support.

## Current architecture

```text
ammars-pc local game folder
  /mnt/nvme/Games/<game>
          |
          | direct copy for games not archived yet
          v
Steam Machine local SSD
  /home/deck/Games/<game>
          |
          +-- Steam non-Steam shortcut
          +-- Proton prefix
                    |
                    v
       ~/Games/Saves/live/<game>
                    |
                Syncthing
                    |
                    v
Theoden
  /mnt/storage/games/saves
  daily restic snapshots
```

Finished games may also move through the theoden archive at `/mnt/storage/games/library`. The Steam Machine always runs its local copy.

The stock SteamOS user may not be `deck` on this hardware. Run `whoami` and `printf '%s\n' "$HOME"` before using any path below.

## Observed LEGO Batman layout

The game is not in the theoden game library. It is a ready-to-run 40 GiB portable folder on `ammars-pc`:

```text
/mnt/nvme/Games/LEGO Batman Legacy of the Dark Knight [Portable by SeleZen]
```

The working desktop Steam shortcut uses:

```text
Executable: /mnt/nvme/Games/LEGO Batman Legacy of the Dark Knight [Portable by SeleZen]/LEGOBatmanLotDK/Binaries/Win64/LEGOBatmanLotDK-Win64-Shipping.exe
Start in:   /mnt/nvme/Games/LEGO Batman Legacy of the Dark Knight [Portable by SeleZen]/LEGOBatmanLotDK/Binaries/Win64/
Proton:     Proton Experimental
Options:    none
```

The desktop shortcut's generated compatdata ID is `3404528884`. The Steam Machine will generate a different ID.

Ludusavi already backs up this game to:

```text
/mnt/nfs/games/saves/ammars-pc/Lego Batman_ Legacy of the Dark Knight
```

# Phase 1: Use LEGO Batman on stock SteamOS

## 1. Copy the game directly from the desktop

The Steam Machine must run a local copy. There is no need to move this game through theoden first.

Copy the complete folder from `ammars-pc` to:

```text
/home/deck/Games/LEGO Batman Legacy of the Dark Knight [Portable by SeleZen]
```

Use Dolphin over SFTP or `rsync` after SSH works. Check that the target has at least 40 GiB free first.

For later games already archived on theoden, copy through:

```text
smb://theoden/storage/games/library/
```

Do not add a system-wide NFS setup only for this game.

## 2. Add the known working executable to Steam

In Desktop Mode:

1. Open Steam.
2. Select **Games → Add a Non-Steam Game**.
3. Browse to `LEGOBatmanLotDK-Win64-Shipping.exe` under the local copied folder.
4. Set **Start In** to that executable's `Win64` directory.
5. Force Proton Experimental under **Properties → Compatibility**.

Use no launch options at first. This matches the working desktop shortcut.

Do not add the small top-level `LEGOBatmanLotDK.exe`. Do not use SteamTools or any tool that changes Steam licenses or manifests.

## 3. Create the Steam Machine prefix

Launch the game once. Create a temporary save, then exit cleanly.

Find the new save folder:

```bash
find "$HOME/.local/share/Steam/steamapps/compatdata" \
  -type d \
  -path '*/pfx/drive_c/users/steamuser/AppData/Local/Warner Bros. Interactive Entertainment/LEGO Batman - Legacy of the Dark Knight/SaveGames' \
  -print
```

The real save path ends with:

```text
Warner Bros. Interactive Entertainment/LEGO Batman - Legacy of the Dark Knight/SaveGames/steam/<Steam64ID>
```

The game also stores settings under:

```text
AppData/Local/Dinner/Saved/Config/Windows
```

Sync gameplay saves. Let Ludusavi back up the settings.

## 4. Put the live save inside the existing Syncthing folder

Do not create a second Syncthing folder inside the existing `game-saves` folder. Overlapping Syncthing folders are unsafe.

Use this shared live-save directory on each gaming machine:

```text
~/Games/Saves/live/lego-batman-legacy/SaveGames
```

On the desktop:

1. Stop the game.
2. Move the existing `SaveGames` directory from compatdata into that shared path.
3. Replace the old `SaveGames` directory with a symbolic link to the shared path.

On the Steam Machine:

1. Stop the game.
2. Remove only the empty test `SaveGames` directory.
3. Link that path to its local `~/Games/Saves/live/lego-batman-legacy/SaveGames` copy.

The existing `game-saves` Syncthing share then moves the live saves through theoden. The existing restic job versions the theoden copy.

Do not sync:

- The complete `compatdata` directory.
- The complete Proton prefix.
- The 40 GiB game directory.
- Steam's `shortcuts.vdf`.

Never play on both machines at once. Wait for Syncthing to show **Up to Date** before switching machines.

# Phase 2: Save sync on stock SteamOS

## 5. Use a small Home Manager profile

Home Manager is a good fit for stock SteamOS save sync. It can own the Syncthing user service and Ludusavi without changing SteamOS itself.

Use a dedicated profile. Do not reuse the full workstation or gaming profile.

A Flatpak remains the fallback if the SteamOS `/nix` mount is missing or does not persist.

## 6. Limit Home Manager to user-level save tools

Home Manager works on stock SteamOS for user packages and user services. SteamOS 3.5 and later normally provide a persistent `/nix` mount backed by the home partition.

Check first:

```bash
findmnt /nix
whoami
printf '%s\n' "$HOME"
```

If `/nix` is persistent, add a dedicated standalone Home Manager output later:

```text
hosts/steammachine-steamos/home.nix
homeConfigurations."deck@steammachine"
```

Use the real stock SteamOS username instead of assuming `deck`.

The profile should contain only:

- `services.syncthing.enable = true`
- `pkgs.ludusavi`
- A Ludusavi backup timer, if wanted
- Small shell tools needed for save management

Do not import `_profiles/essentials/home.nix` unchanged. It hardcodes user `ammar` and `/home/ammar`.

Do not import the complete gaming Home Manager module. It installs Hydra and many tools that stock SteamOS already replaces.

Home Manager cannot manage the SteamOS kernel, firmware, bootloader, Gamescope session, system NFS mounts, or system packages.

If `/nix` is absent or does not persist, keep the Flatpak or user-local setup. Do not disable SteamOS read-only mode for save sync.

## 7. Keep Ludusavi as the backup layer

When several games need save protection:

1. Let Syncthing sync the live save folders.
2. Let Ludusavi write host-specific backups under `~/Games/Saves/steammachine`.
3. Sync that backup directory to theoden.
4. Let theoden's existing restic job keep versioned snapshots.

Do not run automatic Ludusavi restores. Restore manually so an old backup cannot overwrite a newer save.

# Phase 3: Full Jovian NixOS replacement later

## 8. Recheck upstream before implementation

Jovian PR #584 added Valve Steam Machine `fremont` support. The researched pin is:

```text
c8ed6729a8eee4268b96a4cc1ae1ace59335e4df
```

Before implementation:

1. Check whether PR #584 merged.
2. Use released Jovian support if available.
3. Otherwise add a separate `jovian-fremont` input at that commit.
4. Keep `steamdeck` on `inputs.chaotic.vendored.jovian`.

Do not move every Jovian host to the unmerged branch.

## 9. Add the future host

Create and immediately stage:

```text
hosts/steammachine/configuration.nix
hosts/steammachine/disk-config.nix
hosts/steammachine/hardware-configuration.nix
hosts/steammachine/home.nix
```

Wire `nixosConfigurations.steammachine` and `checks.x86_64-linux.nixos-steammachine` in `flake.nix`.

Use a managed Home Manager user. One NixOS deployment should update both the system and the home configuration.

## 10. Configure the Jovian host

Use:

```nix
jovian = {
  devices.steammachine = {
    enable = true;
    enableFwupdBiosUpdates = true;
    autoUpdate = false;
  };
  steam = {
    enable = true;
    autoStart = true;
    user = "ammar";
    desktopSession = "plasma";
  };
};
```

Also configure:

- KDE Plasma 6 for Desktop Mode.
- NetworkManager.
- AMD microcode and redistributable firmware.
- Tailscale with no exit node.
- Theoden mounted read-only at `/mnt/storage`.
- `gaming.enable = true`.
- NixOS Gamescope forced off because Jovian supplies it.
- Ludusavi backups at `/home/ammar/Games/Saves/steammachine`.
- Syncthing for save backups.

Do not copy the Steam Deck host wholesale. Leave out its Decky, CEF, touchscreen, MoonDeck, LSFG-VK, removable-GRUB, and Deck-specific patches.

## 11. Keep firmware changes manual

Keep runtime firmware and `fwupd` support enabled. Keep automatic BIOS updates disabled.

Before a firmware update:

```bash
fwupdmgr get-devices
fwupdmgr get-updates
```

Read the release notes before running:

```bash
sudo fwupdmgr update
```

NixOS generations cannot roll back a BIOS update. The Fremont firmware remote researched in PR #584 used `Keyring=none`, so a Nix source hash is not the same as a Valve firmware signature.

## 12. Use a simple disk layout

Use the internal NVMe with:

- GPT.
- A 512 MiB EFI System Partition.
- One ext4 root partition using the remaining space.
- systemd-boot.
- No disk encryption, so controller-only unattended boot still works.

Use the exact `/dev/disk/by-id/...` path. Do not use `/dev/nvme0n1` for the final destructive install plan.

Prepare Valve recovery media before changing the internal disk.

## 13. Capture machine-specific data

Boot the NixOS installer without changing the disk. Save these outputs:

```bash
ls -l /dev/disk/by-id/
ip link
fwupdmgr get-devices
nixos-generate-config --show-hardware-config
```

Use them to finish:

- `hosts/steammachine/hardware-configuration.nix`
- The Disko device path
- `terraform/devices.tf`
- `terraform/opnsense.tf`
- `lib/hosts.nix`

Use `192.168.1.111` unless it is already assigned.

## 14. Keep the game workflow simple after the switch

Continue to use Hydra only on `ammars-pc`.

Long-term paths:

```text
Theoden archive:       /mnt/storage/games/library
Steam Machine mount:  /mnt/storage/games/library
Local game library:   /home/ammar/Games/Library
Local Wine prefixes:  /home/ammar/Games/Prefixes
Save backups:         /home/ammar/Games/Saves/steammachine
```

Copy each wanted game to the local SSD. Add a normal non-Steam shortcut. Use UMU or Steam Proton without changing Steam license data.

Do not build automatic Steam shortcut generation until manual copying becomes a real problem. Steam must be closed when external tools edit `shortcuts.vdf`, and Steam can overwrite concurrent changes.

For installers, run the installer once in Plasma Desktop Mode with a stable per-game prefix. Keep prefixes outside replaceable game folders.

## 15. Validate before installation

Run:

```bash
nixfmt hosts/steammachine/*.nix
nix flake check --no-build
nix build .#checks.x86_64-linux.nixos-steammachine
nix build .#nixosConfigurations.steammachine.config.system.build.toplevel
```

For the DHCP reservation:

```bash
cd terraform
tofu plan
```

Review the plan before `tofu apply`.

## 16. Test the installed system in stages

Test the base system before optional plugins:

- Gaming Mode and Plasma switching.
- Audio, HDMI, HDR, VRR, Wi-Fi, Bluetooth, and Ethernet.
- Suspend and controller wake.
- Steam Machine LEDs and firmware visibility.
- Local launch of one DRM-free game.
- Syncthing backup and manual restore.

Add Decky, MoonDeck, LSFG-VK, BoilR, or Steam ROM Manager only after the base system works and a real need exists.

## Files for the future switch

| File | Planned change |
|------|----------------|
| `flake.nix` | Add isolated Fremont input, host, and build check |
| `flake.lock` | Lock the selected Jovian revision |
| `hosts/steammachine/configuration.nix` | Jovian, Plasma, firmware, networking, NFS, managed Home Manager |
| `hosts/steammachine/disk-config.nix` | Internal NVMe Disko layout |
| `hosts/steammachine/hardware-configuration.nix` | Real generated hardware data |
| `hosts/steammachine/home.nix` | Small gaming home profile and save backups |
| `modules/nixos/nfs-client.nix` | Add a read-only mount option if still missing |
| `lib/hosts.nix` | Add the Steam Machine LAN address |
| `terraform/devices.tf` | Add the real MAC address |
| `terraform/opnsense.tf` | Add the DHCP reservation |

## Related plan

- `.agents/plans/2026-05-28-game-save-sync-stack.md` — existing Syncthing, Ludusavi, theoden, and restic design
