# DRM-Free Gaming Stack: Acquisition, Save Sync, and Storage

**Date**: 2026-05-28
**Status**: theoden deployed ✅, restic init ✅, desktop HM blocked by nix daemon max-jobs=0

## Architecture

```
Desktop (ammars-pc) ──── Syncthing ────→ theoden ──── restic → snapshots
       │                    │               │
       │                    │          /mnt/storage/games/saves/
       │                    │          /mnt/storage/games/library/
       │                    │
   ~/Games/Saves/     Deck ~/Games/Saves/
       │                    │
   Ludusavi             Ludusavi
   (hourly timer)       (manual, pre/post-game)
           │                    │
           │  Hydra (appimage)  │  Hydra (flatpak)
           │  + TorBox token    │  + TorBox token
           │  + Lutris fallback │  + Lutris fallback
           │  + Heroic          │  + Heroic
```

| Layer | Tool | Location | Role |
|-------|------|----------|------|
| Acquisition | Hydra Launcher | Desktop (AppImage), Deck (Flatpak) | Browse catalogue, download via TorBox, install, launch with Proton/Wine |
| Fallback launcher | Lutris | Desktop, Deck | Games that need deeper Wine config than Hydra provides |
| Existing launcher | Heroic | Desktop (already installed) | Epic/GOG/Amazon library |
| Game library storage | theoden SMB | `/mnt/storage/games/library/` | Central repo for game installs; Deck copies local before playing |
| Save sync | Syncthing + Ludusavi | Desktop ↔ Deck ↔ theoden | Seamless P2P save sync with versioned backups |
| Save versioning | Restic | theoden | Daily snapshots of `/mnt/storage/games/saves/`, keep 30 days |
| Storage backend | theoden mergerfs + SMB/NFS | Already exists | Unified storage via existing infrastructure |

## Key decisions

- **No Gameyfin**: Hydra already provides a full library UI on every device that can play games. A web-only gallery adds no value.
- **No Questarr**: Games can't be streamed from a server like media. Torrenting on the server doesn't help when you still need to copy 80GB to each client. Hydra + TorBox handles acquisition directly on the gaming device.
- **No Playnite**: Windows-only (Linux support planned for 2026, no release). Even on Windows, it has no repack aggregation — just a "run installer" button for manually downloaded repacks.
- **Hydra via AppImage**: Hydra Launcher is not in nixpkgs. Wrap it as an AppImage derivation using the nvfetcher + appimageTools pattern already established by moondeck-buddy and opendeck.
- **Syncthing 3-way**: Desktop, Deck, and theoden all sync `~/Games/Saves/` (or equivalent). Ludusavi writes backups to `~/Games/Saves/<hostname>/`. Syncthing distributes to all peers. Restic snapshots the theoden copy.
- **Restic local → S3-ready**: Start with a local restic repo on theoden (`/mnt/storage/games/.restic-saves/`). When S3 backup infrastructure is deployed, swap `--repo` to `s3://...`. Same backup command, same retention policy.
- **TorBox**: Hydra handles debrid natively. Just paste the existing TorBox API token into Hydra settings. No separate JDownloader2 or manual steps needed.

## Implementation steps

### 1. Storage directories on theoden

- [x] **1.1** Edit `hosts/servers/theoden/storage.nix` — add tmpfiles rules:
  ```nix
  "d /mnt/storage/games 2775 root storage -"
  "d /mnt/storage/games/library 2775 root storage -"
  "d /mnt/storage/games/saves 2775 ammar storage -"
  ```
  Saves dir owned by `ammar` so both Syncthing (running as ammar's user) and restic (root) can access.

- [x] **1.2** Existing SMB share at `\\theoden\storage` already exposes `/mnt/storage` recursively — no Samba config changes needed. Deck can mount via Dolphin → `smb://theoden/storage`.

### 2. Syncthing on theoden (NixOS service, receive/sync saves)

- [x] **2.1** Add `services.syncthing` to `hosts/servers/theoden/configuration.nix`:
  - Declare folder `/mnt/storage/games/saves/` with folder ID `game-saves`
  - Add firewall ports: 22000 (TCP+UDP) for Syncthing device discovery
  - Initial device introduction via web UI (`http://theoden.lan:8384`) — device IDs are per-install and need manual pairing

- [x] **2.2** Open firewall ports for Syncthing:
  ```nix
  networking.firewall.allowedTCPPorts = [
    # ... existing ...
    8384  # Syncthing web UI
    22000 # Syncthing sync protocol
  ];
  networking.firewall.allowedUDPPorts = [
    # ... existing ...
    22000 # Syncthing device discovery (broadcast)
  ];
  ```

### 3. Restic save versioning on theoden

- [x] **3.1** Add systemd service to `hosts/servers/theoden/configuration.nix`:
  ```
  Service: restic backup /mnt/storage/games/saves \
           --repo /mnt/storage/games/.restic-saves
  Timer: daily, randomized delay 1h
  ```

- [x] **3.2** Configure retention policy (`restic forget --keep-daily 30 --prune`)

- [ ] **3.3** Initialize restic repo (one-time manual step after deploy):
  ```bash
  restic init --repo /mnt/storage/games/.restic-saves
  ```

- [x] **3.4** Design the systemd service to accept an `S3_REPO` env var for future S3 migration. When set, `--repo` uses the S3 URL instead of local path.

### 4. Syncthing on desktop (Home Manager, sync saves)

- [x] **4.1** Add `services.syncthing` to the existing dendritic gaming module (`modules/dendritic/gaming.nix`, HM class):
  ```nix
  services.syncthing = {
    enable = lib.mkIf cfg.syncthing.enable true;
    settings = {
      folders."game-saves" = {
        path = "${config.home.homeDirectory}/Games/Saves";
        id = "game-saves";
        devices = [ /* paired via web UI */ ];
      };
    };
  };
  ```

- [x] **4.2** Add `syncthing` sub-option to gaming module:
  ```nix
  options.gaming.syncthing = {
    enable = lib.mkEnableOption "Syncthing save sync";
  };
  ```

### 5. Ludusavi on desktop (save backup)

- [x] **5.1** Add `pkgs.ludusavi` to `modules/dendritic/gaming.nix` HM class `home.packages`

- [x] **5.2** Add `ludusavi` sub-option to gaming module:
  ```nix
  options.gaming.ludusavi = {
    enable = lib.mkEnableOption "Ludusavi save backup" // { default = true; };
    backupPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Games/Saves/${config.networking.hostName}";
    };
    timerInterval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
    };
  };
  ```

- [x] **5.3** Add systemd user timer + service for Ludusavi:
  ```
  Service: ludusavi backup --path <backupPath> --force
  Timer: OnCalendar=hourly
  ```

- [x] **5.4** Default `ludusavi.enable = config.gaming.enable` (auto-enabled when gaming is on)

### 6. Lutris (fallback launcher)

- [x] **6.1** Add `pkgs.lutris` to `modules/dendritic/gaming.nix` HM class `home.packages` (alongside existing `heroic`)

### 7. Hydra Launcher (acquisition via AppImage wrapper)

- [x] **7.1** Add Hydra to nvfetcher sources: track GitHub releases from `hydralauncher/hydra`, extract the `.AppImage` asset

- [x] **7.2** Regenerate `_sources/generated.nix`

- [x] **7.3** Create `modules/dendritic/hydra.nix` — dendritic aspect following the moondeck/opendeck pattern:
  ```nix
  # HM aspect only (no NixOS system components needed for a desktop app)
  flake.aspects.hydra.homeManager =
    { pkgs, lib, config, ... }:
    let
      sources = import ../../_sources/generated.nix { ... };
      mkHydraAppImage = pkgs.appimageTools.wrapType2 {
        pname = "hydra-launcher";
        inherit (sources.hydra-launcher) version src;
        extraPkgs = _: [];  # no extra dependencies needed
      };
    in {
      options.hydra = {
        enable = lib.mkEnableOption "Hydra Launcher";
      };
      config = lib.mkIf config.hydra.enable {
        home.packages = [ (mkHydraAppImage pkgs) ];
      };
    };
  ```

- [x] **7.4** Wire the hydra dendritic module into `flake.nix` HM module imports (following existing moondeck/opendeck pattern)

- [x] **7.5** Enable in `hosts/desktop/home.nix`: `hydra.enable = true`

### 8. Steam Deck setup (manual, not Nix)

- [ ] **8.1** Install Syncthing from Flathub/Discover
- [ ] **8.2** Configure Syncthing to sync `/home/deck/Games/Saves/` with the same `game-saves` folder ID
- [ ] **8.3** Install Ludusavi from Flathub/Discover
- [ ] **8.4** Configure Ludusavi backup path: `/home/deck/Games/Saves/deck/`
- [ ] **8.5** Install Hydra from Flathub, configure TorBox token
- [ ] **8.6** For game transfers: Switch to Desktop Mode → Dolphin → `smb://theoden/storage/games/library/` → copy game folder to SD card or internal SSD. Add executable as non-Steam game in Steam, force Proton.
- [ ] **8.7** For restore before playing: run `ludusavi restore` (can be added as a Steam shortcut for convenience)

### 9. Git stage and deploy

- [x] **9.1** `git add` all new files
- [x] **9.2** `git add` all modified files
- [x] **9.3** Deploy theoden: `deploy .#theoden`
- [x] **9.4** Initialize restic repo on theoden: `ssh theoden.lan restic init --repo /mnt/storage/games/.restic-saves`
- [ ] **9.5** Desktop: `nh home switch` — blocked by `max-jobs = 0` in nix.conf (pre-existing, affects lutris/steam i686 builds)
- [ ] **9.6** Pair Syncthing devices via web UIs (one-time)
- [ ] **9.7** Configure Hydra TorBox token in app settings

## Files changed/created

| File | Action |
|------|--------|
| `hosts/servers/theoden/storage.nix` | Edit — `games/` tmpfiles rules |
| `hosts/servers/theoden/configuration.nix` | Edit — Syncthing service, restic service+timer, firewall ports |
| `modules/dendritic/gaming.nix` | Edit — Syncthing (HM), Ludusavi pkg+config+timer, Lutris pkg, add sub-options |
| `modules/dendritic/hydra.nix` | **Create** — Hydra AppImage wrapper (dendritic aspect) |
| `_sources/nvfetcher.toml` | Edit — hydra-launcher source entry |
| `_sources/generated.nix` | Regenerate — (auto-generated by nvfetcher) |
| `hosts/desktop/home.nix` | Edit — `hydra.enable = true` |
| `flake.nix` | Edit — wire hydra dendritic aspect into HM module imports |

## Non-Nix manual steps

| Step | Device | Notes |
|------|--------|-------|
| Syncthing pairing | Desktop + theoden + Deck | Open each web UI, add device IDs (one-time) |
| Restic repo init | theoden | `restic init --repo /mnt/storage/games/.restic-saves` |
| Hydra TorBox token | Desktop + Deck | Paste API token in Hydra settings |
| Deck Syncthing + Ludusavi | Steam Deck | Install via Flathub, configure paths |
| Deck game transfer | Steam Deck | Dolphin → SMB mount → copy to local storage |
| Deck non-Steam shortcuts | Steam Deck | Add game .exe, force Proton in Compatibility |
