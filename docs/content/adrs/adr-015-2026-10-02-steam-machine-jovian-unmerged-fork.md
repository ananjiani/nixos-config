---
date: 2026-10-02
title: Steam Machine runs Jovian NixOS from an unmerged fork branch
status: accepted
supersedes:
superseded_by:
systems: [steammachine, steamdeck, jovian, nixos-anywhere]
tags: [deployment, hardware, steam, jovian, flake-inputs, firmware]
---

## Context and Problem Statement

Valve shipped the Steam Machine (hardware codename `fremont`) in 2026. It runs stock SteamOS, which works but is not declarative, so none of this repository's existing machinery applies to it: no SoPS, no Syncthing folder, no Ludusavi timer, no per-host Nix configuration. The machine is intended to live in the living room and play DRM-free games sourced from the theoden archive, which requires save sync shared with `ammars-pc` and the Steam Deck.

Jovian NixOS already runs on the Steam Deck here. Its Steam Machine support is unmerged upstream ([PR #584](https://github.com/Jovian-Experiments/Jovian-NixOS/pull/584)), which at the time of this decision was open, conflicted with upstream `development`, and carried 47 review comments across 20 commits. So the question is not only "NixOS or SteamOS" but "how do we take a hardware port that upstream has not accepted yet".

## Decision Drivers

- Declarative system configuration, since that is the entire reason this repository exists
- Save sync must reuse the existing Syncthing `game-saves` folder and the Ludusavi backup wrapper, not fork them
- The Steam Machine is nearly empty (one game, ~7.5 GB), so a failed install is cheap to repeat
- The Steam Deck is working and must not be destabilised by a port that is still in review
- Steam itself must stay unmodified: no SteamTools, LuaTools, Millennium or SLSsteam, and no writes to `shortcuts.vdf`
- A BIOS update cannot be rolled back by a NixOS generation, so firmware flashing must stay manual

## Considered Options

1. **Keep stock SteamOS, layer Home Manager on it** for user-level save sync only
2. **Wait for PR #584 to merge**, then install released Jovian NixOS
3. **Install Jovian NixOS now, pinned to the PR author's fork branch** (chosen)

## Decision Outcome

Chosen option: **install Jovian NixOS now, pinned to the author's fork branch**, because declarative configuration and shared save sync are the point of the exercise, the machine is cheap to reinstall, and waiting indefinitely on an unmerged port blocks the actual goal. The pin is `github:duckysocks22/Jovian-NixOS/development`, resolved by `flake.lock` to `022c153e5e0cbf2056b3b9b9f4dffb80e986c691`.

Three choices accompany the pin:

1. **A separate flake input**, `jovian-fremont`, imported only by `hosts/steammachine`. The Steam Deck keeps `inputs.chaotic.vendored.jovian`, so a bad pin cannot affect a working device.
2. **No `nixpkgs.follows`.** The fork keeps its own nixpkgs. Jovian requires nixos-unstable and the host already runs on `nixpkgs-unstable`, so following would not remove a build, and not following keeps the fork's own resolution intact.
3. **`enableFwupdBiosUpdates = true` with `autoUpdate` left at its default of `false`.** Firmware discovery and `fwupd` stay available, but flashing happens only when a human runs `fwupdmgr update`.

### Consequences

- Good: The host is fully declarative, and one `nixos-anywhere` run covers both system and user configuration through managed Home Manager.
- Good: Save sync reuses the existing `game-saves` Syncthing folder and the Ludusavi wrapper, so there is one definition of save handling rather than two.
- Good: `flake.lock` records the exact commit. The branch may move, but builds stay reproducible until someone deliberately runs `nix flake lock --update-input jovian-fremont`.
- Good: The Steam Deck is untouched by the pin, so the port can fail without taking a working device with it.
- Bad: The pinned revision is unmerged and conflicted with upstream `development`. A rebase or force-push can change or remove it, and a lock update may then bring unrelated changes.
- Bad: If the author deletes the branch once the PR merges or closes, the input 404s and **flake evaluation fails for every host**, since inputs are resolved globally before any per-host configuration is considered. That is the single largest failure mode of this decision.
- Bad: "Initial support" is literal. The module supplies the Valve kernel, firmware and `jovian.hardware.has.amd.gpu`. It does not add fremont-specific thermal or session tuning.
- Bad: No HDMI-CEC. It exists only on a divergent fork branch that is 26 commits behind and reintroduces `Keyring=none`, which disables firmware signature verification. Trading signature verification for a TV remote is not a good exchange.
- Bad: OS fan control and Valve's Mesa forks (`jovian.steamos.enableVendorDrivers`) are on by default, inherited from the Deck's tuning. They are unvalidated on this thermal design, so the fan curve needs watching on first boot.
- Bad: The first build may compile `linux_jovian` from source, because no chaotic substituter is configured for this host.
- Neutral: Superseding this ADR is expected and cheap. Once PR #584 merges, move to released Jovian, delete the `jovian-fremont` input, and drop the extra commit pin.

### Confirmation

- CI evaluates and builds the host: `configure`, `show x86_64-linux` and `build checks.x86_64-linux.nixos-steammachine` all succeed.
- `flake.lock` records `duckysocks22/Jovian-NixOS` at `022c153e5e0cbf2056b3b9b9f4dffb80e986c691`, and `hosts/steamdeck/configuration.nix` still imports `inputs.chaotic.vendored.jovian`.
- After install: Gaming Mode and Plasma switching, controller input, suspend, LEDs, HDMI, HDR and VRR all work, and `fwupdmgr get-devices` reports the current BIOS without flashing anything.
- Save sync round-trips: a save written on the Steam Machine reaches theoden and back to the desktop.

## Pros and Cons of the Options

### Keep stock SteamOS, layer Home Manager on it

- Good: No disk wipe, no recovery media, and no risk to a working living-room device.
- Good: Home Manager does install and run on SteamOS, with `/nix` persistent since SteamOS 3.5.
- Bad: User-level only. No kernel, firmware, bootloader, Gamescope session or system service can be managed.
- Bad: The Steam Machine would be the only host where the configuration does not describe the system, which puts it permanently outside the repository's model.
- Bad: Two package worlds to keep in sync, and a second place where save sync could be configured differently by accident.

### Wait for PR #584 to merge

- Good: No pin, no fork, no risk of an input disappearing, and released Jovian is reviewed by its maintainers.
- Good: Zero maintenance burden from tracking someone else's development branch.
- Bad: No schedule. The PR was conflicted and had 47 review comments, so "soon" is not an estimate anyone can act on.
- Bad: Blocks the actual goal indefinitely to avoid a cost that, on an empty machine, is a couple of hours.

### Install now, pinned to the fork branch (chosen)

- Good: Working hardware support today, with the Valve kernel, firmware and GPU flag.
- Good: The pin is isolated to one host, so the Deck and the rest of the fleet are unaffected.
- Bad: Tracks an unreviewed, unmerged branch that can move at any time.
- Bad: A deleted branch breaks flake evaluation fleet-wide, not just for this host.
- Neutral: A kernel source build is likely on first use, and pushes to the Attic cache afterwards, which incidentally warms it for the Steam Deck.
