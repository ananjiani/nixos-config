# Steam Deck Jovian NixOS Configuration

**Date**: 2026-05-29
**Status**: In progress — code complete, awaiting Deck hardware for deployment

## Summary

Replace SteamOS on the Steam Deck with NixOS + Jovian, reusing existing modules (gaming, Tailscale, Syncthing, Ludusavi, secrets) from the dotfiles repo. Managed Home Manager (one `nixos-rebuild` deploys everything). Initial install via `nixos-anywhere` from desktop, no keyboard needed on the Deck.

## Architecture decisions

- **Jovian NixOS** (not stock SteamOS) — enables declarative config reuse from the dotfiles repo: gaming module, Tailscale, secrets (SOPS/vault-agent), Syncthing, Ludusavi
- **Chaotic-Nyx binary cache** — avoids 3-hour kernel compiles on Deck hardware
- **Managed Home Manager** — `home-manager` NixOS module (not standalone). Single `nixos-rebuild --target-host` deploys everything. No separate `nh home switch`
- **NFS mount from theoden** — Deck mounts `/mnt/storage` via NFS for direct game library access (same as desktop)
- **LAN hostnames** — `networking.nix` provides `/etc/hosts` resolution
- **No Mullvad VPN** — Deck connects directly (no VPN bypass needed)
- **KDE Plasma** for Desktop Mode (Dolphin SMBA browser, Konsole, Brave)
- **Initial install via `nixos-anywhere`** — flash the repo's ISO to USB, boot Deck from it, SSH in from desktop, deploy from flake

## Import decisions

### NixOS (configuration.nix imports) — kept

| Module | Reason |
|--------|--------|
| `_profiles/base.nix` | SSH, hostPlatform, essential packages |
| `_profiles/secrets.nix` | vault-agent, SOPS age key |
| `modules/nixos/bluetooth.nix` | Controller support |
| `modules/nixos/tailscale.nix` | Mesh access (no exit node) |
| `modules/nixos/networking.nix` | LAN hostname resolution (`theoden.lan`, etc.) |
| `modules/nixos/nfs-client.nix` | Mount theoden game library at `/mnt/storage` |

### NixOS (configuration.nix imports) — skipped

| Module | Reason |
|--------|--------|
| `modules/nixos/amd.nix` | Jovian's Steam Deck module handles amdgpu/initrd already |
| `modules/nixos/privacy.nix` | Mullvad VPN — no VPN on Deck |
| `modules/nixos/android.nix` | ADB/Android tools — not on Deck |
| `modules/nixos/openconnect.nix` | Work VPN |
| `modules/nixos/fonts.nix` | KDE ships fonts; Emacs fonts not needed |
| `hosts/desktop/samba.nix` | SMB server — Deck is client only |
| Docker, Sunshine, niri/hyprland | Not a workstation |

### NixOS (flake-level dendritic modules)

| Module | Reason |
|--------|--------|
| `gaming` (NixOS class) | Steam, gamemode, gamescope, steamtinkerlaunch, gamescope-wsi |
| `brave` (NixOS class) | Brave browser with sync, policies, SearXNG search |

### Home Manager (home.nix imports) — kept

| Module | Reason |
|--------|--------|
| `_profiles/essentials/home.nix` | Core terminal tools, git, shell defaults, HM bootstrap |
| `gaming` (HM class, via flake dendritic wiring) | Ludusavi, Syncthing, MangoHUD, Vesktop, Hydra, UMU, protontricks, heroic |

### Home Manager (home.nix imports) — skipped

| Module | Reason |
|--------|--------|
| All of `_profiles/workstation/home.nix` | No Emacs, foot, firefox, dev tools, Hyprland, wallpaper, writing, lf, atuin |

## Implementation steps

### 1. Flake inputs

- [x] **1.1** Add `chaotic` input: (already existed in flake.nix)
  ```nix
  chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  ```
- [x] **1.2** Add `jovian` input (with nixpkgs follows for clean lockfile):
  ```nix
  jovian.url = "github:Jovian-Experiments/Jovian-NixOS";
  jovian.inputs.nixpkgs.follows = "nixpkgs";
  ```

### 2. Create `hosts/steamdeck/disk-config.nix`

- [x] **2.1** Simple GPT layout for `/dev/nvme0n1`:
  ```nix
  { lib, ... }:
  {
    disko.devices = {
      disk.main = {
        device = lib.mkDefault "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              name = "ESP";
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "fmask=0077" "dmask=0077" ];
              };
            };
            root = {
              name = "root";
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  }
  ```

### 3. Capture `hosts/steamdeck/hardware-configuration.nix`

- [ ] **3.1** Boot the repo's ISO on the Deck (build with `nix build .#iso`, burn to USB)
- [ ] **3.2** SSH in as root: `ssh root@<deck-ip>` (password: `nixos`, SSH key pre-authorized)
- [ ] **3.3** Run `nixos-generate-config --show-hardware-config` and copy output
- [x] **3.4** Commit the hardware config to `hosts/steamdeck/hardware-configuration.nix` (placeholder created; must replace with real output before deploy)

### 4. Create `hosts/steamdeck/configuration.nix`

- [x] **4.1** Imports block: hardware-config, disk-config, Jovian, Chaotic, home-manager, profiles, NixOS modules
- [x] **4.2** Jovian config: `devices.steamdeck.enable`, `steam.autoStart`, `user = "ammar"`, `desktopSession = "plasma"`
- [x] **4.3** Gaming NixOS class: `gaming.enable = true`
- [x] **4.4** Tailscale: `modules.tailscale.enable`, `operator = "ammar"`, `useExitNode = null`
- [x] **4.5** Bluetooth: imported `modules/nixos/bluetooth.nix` (no enable option — always-on when imported)
- [x] **4.6** KDE Plasma: `services.desktopManager.plasma6.enable`
- [x] **4.7** Brave: `programs.brave.enable`, `package = pkgs.brave-origin`, `features.sync`, `searchEngine` pointing at `searxng.lan`, `doh.enable = false`
- [x] **4.8** PipeWire audio: full enable (audio, alsa, pulse) — Jovian's steamdeck sound module handles this; added 32-bit alsa support
- [x] **4.9** Firmware: `hardware.enableRedistributableFirmware`, `hardware.cpu.amd.updateMicrocode`
- [x] **4.10** User `ammar`: `wheel`, `video`, `audio` groups, `initialPassword = "temp"`
- [x] **4.11** Managed Home Manager: `home-manager.users.ammar = import ./home.nix`

### 5. Create `hosts/steamdeck/home.nix`

- [x] **5.1** Import `_profiles/essentials/home.nix`
- [x] **5.2** Gaming HM class:
  ```nix
  gaming = {
    enable = true;
    syncthing.enable = true;
    ludusavi.backupPath = "/home/ammar/Games/Saves/steamdeck";
  };
  ```

### 6. Wire into `flake.nix`

- [x] **6.1** Add `nixosConfigurations.steamdeck` (with brave-origin overlay + dendritic NixOS + HM modules)
- [x] **6.2** Add `checks.${system}.nixos-steamdeck`
- [x] **6.3** Do NOT add `homeConfigurations."ammar@steamdeck"` — managed HM via NixOS module, no standalone `nh home switch`

### 7. Git stage and validate

- [x] **7.1** `git add hosts/steamdeck/` (all 4 files)
- [x] **7.2** `git add flake.nix`
- [x] **7.3** `nix flake lock --update-input jovian` (chaotic already pinned; pin new jovian input)
- [x] **7.4** `nix flake check --no-build` — passed, all configurations evaluate successfully

### 8. Deploy (initial install via nixos-anywhere)

- [ ] **8.1** Build ISO: `nix build .#iso` — flash to USB/SD card
- [ ] **8.2** On Deck: Vol Down + Power → boot menu → select USB
- [ ] **8.3** From desktop: SSH into live ISO: `ssh root@<deck-ip>` (verify connectivity)
- [ ] **8.4** Deploy: `nixos-anywhere --flake .#steamdeck root@<deck-ip>`
  - Disko partitions NVMe
  - nixos-install runs
  - Deck reboots into Jovian NixOS

### 9. Post-install manual steps

- [ ] **9.1** After reboot: Deck lands in Gaming Mode. Switch to Desktop Mode
- [ ] **9.2** Change user password: `passwd` (initial was `temp`)
- [ ] **9.3** Copy age key: `scp ~/.config/sops/age/keys.txt ammar@steamdeck.lan:.config/sops/age/`
- [ ] **9.4** Connect to Tailscale: `sudo tailscale up` (or `tailscale up --operator=ammar`)
- [ ] **9.5** SSH key exchange: `ssh-copy-id ammar@steamdeck.lan` (for passwordless future deploys)
- [ ] **9.6** Pair Syncthing devices via web UI (`localhost:8384`) — desktop ↔ Deck ↔ theoden
- [ ] **9.7** Sign into Brave Sync
- [ ] **9.8** Verify: NFS mount (`ls /mnt/storage/games/library/`), Syncthing folder, Ludusavi timer

### 10. Ongoing maintenance

- [ ] **10.1** All future deploys: `nixos-rebuild switch --target-host ammar@steamdeck.lan --use-remote-sudo --flake .#steamdeck`
- [ ] **10.2** Firmware updates: boot SteamOS recovery USB (2-3x/year) — Jovian doesn't handle Steam Deck BIOS/firmware
- [ ] **10.3** `nix flake update` pulls Jovian + Chaotic updates alongside nixpkgs

## Deck-specific configuration summary

| Component | How |
|-----------|-----|
| Game launcher / repack acquisition | Hydra (from `gaming` HM module), TorBox token in-app |
| Save sync | Ludusavi → `~/Games/Saves/steamdeck/` → Syncthing → desktop + theoden |
| Save versioning | Restic on theoden (already deployed — `game-save-sync-stack` plan) |
| Game library access | NFS mount from theoden (`/mnt/storage`) |
| Game install workflow | Desktop: Hydra installs to `/mnt/storage/games/library/<Game>/`. Deck: Dolphin → copy to local SSD → add as non-Steam game in Steam |
| Legit GOG/Epic games | Junk Store (Decky plugin) in Game Mode |
| Non-Steam game presentation | MetaDeck + SteamGridDB (Decky plugins) |
| Achievements (cracked) | Sentinel (optional, AppImage) |
| Browser | Brave (declarative, syncs with desktop via Sync) |
| Remote management | `nixos-rebuild --target-host` from desktop |
| Firmware updates | SteamOS recovery USB (manual, 2-3x/year) |

## Related plans

- `2026-05-28-game-save-sync-stack.md` — DRM-free game acquisition + save sync (theoden restic, Syncthing, Ludusavi, Hydra)
