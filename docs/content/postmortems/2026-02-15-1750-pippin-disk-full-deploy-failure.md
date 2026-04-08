---
date: 2026-02-15
title: Pippin deploy failed due to full disk
severity: moderate
duration: 0h 35m
systems: [pippin, deploy-rs]
tags: [nixos, storage, deploy-rs, nix-gc]
commit: https://codeberg.org/ananjiani/infra/commit/ebcd278
---

## Summary

A deploy-rs deployment to pippin (OpenClaw AI assistant VM) failed because the 32GB root filesystem was full. Home Manager activation couldn't create temporary directories, triggering a deploy-rs rollback that also partially failed due to the same disk pressure. DNS was left broken on the VM as a side effect.

## Timeline

All times CST.

- **17:27** - deploy-rs deployment to pippin fails. `home-manager-ammar.service` reports `No space left on device` when creating `/tmp/nix-build-*` directory. `attic-watch-store.service` also crash-loops.
- **17:27** - deploy-rs magic rollback activates, reverts from generation 84 to 83. Re-activation of the previous generation also fails with the same disk space error, producing a cascading error.
- **17:27** - Rollback leaves `/etc/resolv.conf` empty (0 bytes), breaking all DNS resolution on pippin. `host` queries resolve against localhost, which has no resolver running.
- **17:35** - Investigation begins. `df -h` shows 82% usage even after `nix-collect-garbage -d` frees 5.7GB (515 store paths). Base system with Chromium, Python3, and OpenClaw consumes ~25GB on its own.
- **17:40** - Decision to increase disk from 32GB to 48GB. `tofu plan` shows no changes due to `lifecycle { ignore_changes = [disk] }` — disk resize done directly via Proxmox CLI (`qm resize 105 scsi0 48G`).
- **17:45** - Back up SSH host keys (ed25519 + RSA) from pippin to preserve SOPS age identity.
- **17:49** - First nixos-anywhere attempt fails — pippin can't resolve `github.com` because resolv.conf is empty. Manually write nameservers to `/etc/resolv.conf`.
- **17:50** - Second nixos-anywhere run with `--extra-files` for SSH keys. Kexec boots, disko partitions the full 48GB, NixOS installs from scratch.
- **18:03** - Pippin boots successfully. `df -h` shows 7.5GB used / 38GB free (17%). Home Manager activates cleanly. SOPS decrypts with preserved age key.

## What Happened

A routine deploy-rs deployment to pippin hit a wall: the 32GB root filesystem was too full for Home Manager to create temporary build directories. The Nix store had accumulated old generations over time without aggressive enough garbage collection — the GC was configured for 30-day retention, and on a 32GB VM running Chromium and a full Python environment, that's far too generous.

The deploy-rs magic rollback kicked in as designed, but since the underlying problem was disk space (not a bad configuration), the rollback couldn't re-activate the previous generation either. This left the system in a partially broken state where `/etc/resolv.conf` was wiped during the activation shuffle, killing DNS.

The fix involved garbage collecting on the live system (which only freed enough to get to 82%), resizing the virtual disk from 32GB to 48GB via the Proxmox API, and then doing a full repave with nixos-anywhere to cleanly partition and install on the larger disk.

## Contributing Factors

- **30-day GC retention on a 32GB disk**: The default GC config in `base.nix` kept generations for 30 days, which is excessive for a small VM where all state is declaratively managed and rebuildable from git.
- **No store optimisation enabled**: `auto-optimise-store` was not configured, meaning identical files across store paths were stored as separate copies rather than hard-linked.
- **Undersized VM disk**: 32GB is tight for a system with Chromium (~600MB), Python with data science packages, and the OpenClaw stack. The base closure alone is ~25GB.
- **`lifecycle { ignore_changes = [disk] }` in Terraform**: This safety measure (preventing accidental VM recreation on disk attribute changes) meant the disk resize couldn't be done through the normal tofu workflow and required out-of-band Proxmox CLI intervention.

## What I Was Wrong About

- **"I thought I had GC set up already"** — GC was configured, but the 30-day retention was far too generous for a 32GB VM. The mental model was "GC is on, so disk will be fine" without considering whether the retention window fit the available storage.
- **"Rollback will recover from activation failures"** — deploy-rs rollback works great for bad configs, but when the failure is environmental (disk full), rolling back to the previous generation hits the same wall.

## What Helped

- **Fully declarative configuration**: Because pippin's entire state (NixOS, Home Manager, OpenClaw, SOPS secrets) is in the flake, a complete repave with nixos-anywhere was a single command — no data loss, no manual reconstruction.
- **nixos-anywhere + disko**: The ability to wipe and reinstall a VM from scratch in minutes made the "nuclear option" trivially easy.
- **Attic binary cache**: The reinstall pulled most packages from theoden's cache rather than rebuilding, making the repave fast.
- **SSH key backup preserved SOPS chain**: Backing up host keys before repaving meant no SOPS re-keying was needed.

## What Could Have Been Worse

- **If pippin had unique local state**: The repave was painless because everything is declarative. A VM with manual config or local databases would have required careful backup/restore.
- **If DNS breakage had affected other services**: Pippin's broken DNS was isolated to the VM itself. If this had been a DNS server (like samwise running AdGuard), the blast radius would have been much larger.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Small VMs with generous GC retention will inevitably hit this. The 30-day default was set once in `base.nix` and applied uniformly regardless of disk size. The fix (3-day retention + auto-optimise) applies globally, but new VMs should be sized with the Nix store closure in mind — not just "how big is the app."

## Action Items

- [x] Reduce GC retention from 30d to 3d in `base.nix`
- [x] Enable `auto-optimise-store` in `base.nix`
- [x] Resize pippin disk from 32GB to 48GB
- [x] Repave pippin with nixos-anywhere on the larger disk
- [ ] Deploy updated `base.nix` to all hosts (boromir, samwise, theoden, pippin)
- [ ] Audit other small VMs for disk headroom relative to their closure size

## Lessons

- **GC retention must be proportional to disk size.** 30 days of generations on a 32GB VM is a ticking time bomb. For declarative systems where everything is rebuildable from git, 3 days is plenty.
- **deploy-rs rollback doesn't help with environmental failures.** It's designed for "new config is bad, revert to old config." When the environment itself (disk, network) is the problem, both old and new generations fail equally.
- **A broken activation can leave DNS in a broken state.** The resolvconf shuffle during NixOS activation can produce an empty `/etc/resolv.conf` if activation fails partway through. This is a subtle secondary failure that blocks further recovery (like nixos-anywhere needing to download kexec).
- **Size VMs for the Nix store, not the application.** The app itself is small, but its Nix closure (with all dependencies) is ~25GB. Always account for the full closure plus room for at least a few generations.
