---
date: 2026-05-21
title: Theoden disk pressure from buildbot GC root accumulation
severity: moderate
duration: ~4d (disk pressure triggered ~May 18, resolved May 21)
systems: [theoden, buildbot-nix, longhorn, k3s]
tags: [nix, ci, storage, kubernetes]
commit: https://codeberg.org/ananjiani/infra/commit/TBD
related: 2026-01-26-buildbot-deploy-rs-cache-inefficiency.md
---

## Summary

Buildbot-nix registered GC roots for every host's full NixOS system closure on theoden, accumulating ~77 GB of pinned store paths on a 197 GB disk shared with Longhorn replicas (78 GB). The disk hit 87% usage, triggering `DiskPressure` on the node. Kubernetes evicted Longhorn daemonsets, CSI plugins, and other pods from theoden, degrading the k3s cluster. Resolved by disabling `registerGCRoots` in buildbot-nix config and relying on the Attic binary cache instead.

## Timeline

All times CDT.

- **~May 18** — Theoden hits disk pressure threshold; kubelet starts evicting pods with `DiskPressure` taint
- **~May 20 20:09** — Rivendell kubelet stops posting status (unrelated — powered off)
- **May 21 ~13:00** — Cluster health check requested; investigation begins
- **May 21 13:05** — Rivendell confirmed NotReady (offline), theoden confirmed DiskPressure
- **May 21 13:10** — Initial hypothesis: old Nix generations not GC'd. Checked — only 1 generation exists, `nix.gc` is configured
- **May 21 13:15** — `nix store gc` frees 18.5 GB of dead paths, but disk still at 76% (141 GB used)
- **May 21 13:20** — Traced disk usage: `/nix/store` at 75 GB, `/var/lib/longhorn/replicas` at 78 GB
- **May 21 13:25** — Discovered buildbot GC roots: `/nix/var/nix/gcroots/per-user/buildbot-worker/ananjiani/infra/x86_64-linux.*` pinning closures for all 8 hosts (~77 GB)
- **May 21 13:30** — Investigated alternatives: NFS relocation (won't work — store paths are local), Attic-only (viable)
- **May 21 13:45** — Confirmed Attic already has all closures; deploy flow (`nix copy --substitute-on-destination`) works without local GC roots
- **May 21 14:00** — Added `branches.disable-gcroots` to `services.buildbot-nix.master` with `registerGCRoots = false`
- **May 21 14:30** — Deployed to theoden (required `NIXOS_NO_CHECK=1` due to dbus→broker switch inhibitor)
- **May 21 14:35** — Removed 15 stale GC roots, ran `nix store gc`: 28,610 paths deleted, 38.5 GB freed
- **May 21 14:36** — Disk usage: 87% → 55% (103 GB used, 85 GB free)

## What Happened

Theoden serves as both a k3s node (running Longhorn storage replicas) and the CI builder (running buildbot-nix master + worker). Buildbot-nix registers GC roots for every successfully built flake output by creating symlinks under `/nix/var/nix/gcroots/per-user/buildbot-worker/`. This is the default behavior — on push to the default branch, every built attribute gets a permanent GC root.

Over time, these GC roots accumulated full NixOS system closures for all hosts in the fleet:

| Attr | Closure Size |
|------|-------------|
| nixos-ammars-pc | 20 GB |
| nixos-framework13 | 15 GB |
| nixos-boromir | 11 GB |
| nixos-pippin | 7 GB |
| nixos-rivendell | 7 GB |
| nixos-theoden | 7 GB |
| nixos-erebor | 5 GB |
| nixos-samwise | 5 GB |
| Home managers, devshell, checks | ~5 GB |

**Total: ~82 GB pinned** — more than the Longhorn replicas (78 GB) on the same 197 GB disk.

When disk usage crossed the kubelet's eviction threshold, theoden got the `node.kubernetes.io/disk-pressure:NoSchedule` taint. DaemonSet pods (longhorn-manager, longhorn-csi-plugin, engine-images, metallb-speaker, alloy) were evicted. This impaired Longhorn volume management on theoden — volumes couldn't attach/mount, blocking pods like `postgres-0` in the stremio namespace.

Compounding the issue, rivendell had been powered off for ~17 hours, leaving ~30 pods stuck in `Terminating` across critical namespaces (flux-system, cert-manager, authentik, traefik).

## Contributing Factors

- **Buildbot-nix default behavior pins all build outputs** — `registerGCRoots` defaults to `true` for the default branch, with no size-based or age-based cleanup
- **Theoden's dual role** (CI builder + k3s storage node) meant buildbot closures competed with Longhorn replicas for the same disk
- **Desktop closures are disproportionately large** — ammars-pc (20 GB) and framework13 (15 GB) with NVIDIA drivers, Hyprland, etc. dwarf server closures
- **No monitoring alert for disk pressure** — the issue went unnoticed for days; the `DiskPressure` taint was only discovered during a manual health check
- **buildbot-nix's tmpfiles rule only cleans `drvs/` subdirectory** — the output-level GC roots (`x86_64-linux.nixos-*`) are permanent, only the per-build derivation links in `drvs/` are cleaned after 7 days

## What I Was Wrong About

- **"nix.gc isn't configured"** — My first assumption was that automatic GC wasn't set up. It was — `nix.gc` runs as configured. But GC can't collect paths that have active GC roots, and all 15 buildbot roots were active.
- **"Old generations are hoarding space"** — Checked and found only 1 generation. The 75 GB in `/nix/store` wasn't from stale generations at all — it was the live closures pinned by buildbot.
- **"Maybe move GC roots to NFS"** — Explored this briefly, but GC roots are just symlinks into `/nix/store`. The store paths themselves are local; you can't move the roots without moving the entire nix store, which would be catastrophically slow on FUSE/mergerfs.
- **"This might need a per-host buildbot worker"** — Considered moving buildbot off theoden entirely. Unnecessary — the real fix was just not pinning what you don't need locally.

## What Helped

- **Attic binary cache already had everything** — All closures were pushed to Attic during build, so disabling GC roots had zero data-loss risk. Rebuilds will fetch from Attic instead of local store.
- **Deploy script uses `nix copy --substitute-on-destination`** — This means the deploy step doesn't need the closure to be locally pinned; it copies from local store (present immediately after build) to the target, and the target fetches missing paths from Attic.
- **`nix path-info -S`** — Quickly showed closure sizes without traversing the entire NAR.
- **`nix store gc --print-dead`** — Revealed 5,460 dead paths (18.5 GB) that the first GC pass cleaned up, buying enough headroom to investigate calmly.

## What Could Have Been Worse

- **If theoden were the sole control plane node**, disk pressure could have taken down etcd and the entire k3s cluster. Having 3 control plane nodes (boromir, samwise, theoden) prevented a total outage.
- **If Longhorn had volumes exclusively on theoden**, the eviction of longhorn-manager/CSI would have caused data unavailability, not just degraded state.
- **If rivendell had been online**, the ~30 Terminating pods would have been running (or at least rescheduling), masking the severity of theoden's eviction cascade.
- **If disk had reached 100%**, the nix daemon itself could have failed, breaking buildbot CI and Attic push entirely.

## Is This a Pattern?

- [x] Pattern: Related to [buildbot-deploy-rs-cache-inefficiency](2026-01-26-buildbot-deploy-rs-cache-inefficiency.md)

The earlier postmortem covered buildbot **redundantly building** the same derivations due to parallel deploy checks. This incident is the complement: buildbot **hoarding the results** of those builds indefinitely. Both stem from buildbot-nix's defaults being optimized for a dedicated CI machine with abundant disk, not a multi-role homelab server.

The broader pattern is: **CI systems on shared infrastructure need explicit resource limits**. Buildbot-nix doesn't know that its GC roots consume disk needed by Longhorn, k3s, or other services on the same machine.

## Action Items

- [x] Disable `registerGCRoots` for all branches in buildbot-nix config
- [x] Remove stale buildbot GC roots from theoden
- [x] Run `nix store gc` to reclaim freed space
- [x] ~~Add a Prometheus alert for disk pressure~~ Already exists: `HostDiskSpaceWarning` (20%) and `NodeDiskPressure` (kubelet condition) were both active. The alerts fired during the incident — the gap was in noticing/responding to them, not in detection.
- [ ] Consider whether buildbot-nix upstream should default to time-limited GC roots (e.g., prune after 7 days) or expose a `gcroots_max_age` option

## Lessons

- **GC roots are invisible hoarders** — `nix.gc` will faithfully run but collect nothing if GC roots pin everything. Check `ls /nix/var/nix/gcroots/per-user/` when GC seems ineffective.
- **CI workers on multi-role servers need explicit disk budgets** — The default buildbot-nix behavior assumes unbounded disk; on a shared node this silently crowds out other workloads.
- **Attic makes local GC roots unnecessary for deploy flows** — Since `nix copy --substitute-on-destination` can fetch from the binary cache, and the build output is guaranteed to be in the local store at deploy time (same buildbot step sequence), permanent GC roots add no safety.
- **Disk pressure on k3s nodes cascades fast** — Longhorn daemonset eviction → volume attach failures → pod stuck in ContainerCreating, all within minutes of crossing the threshold.
