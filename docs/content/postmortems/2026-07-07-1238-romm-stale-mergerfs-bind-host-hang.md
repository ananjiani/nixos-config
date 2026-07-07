---
date: 2026-07-07
title: RomM 502 from stale mergerfs bind mount, escalated to host hang during cleanup
severity: moderate
duration: ~4 days latent (romm degraded), ~30m active investigation, ~6m host outage
systems: [romm, theoden, mergerfs, nfs, podman, nixos, proxmox]
tags: [storage, mergerfs, fuse, stale-mount, podman, nixos, deploy-rs, proxmox]
commit: https://codeberg.org/ananjiani/infra/commit/a93f62de
---

## Summary

RomM returned `502 Bad Gateway` (nginx/1.29.5) because its gunicorn backend couldn't boot: the container's bind-mount of `/romm/library` referenced a mergerfs FUSE instance that had died four days earlier, when a Jul 3 NixOS deploy restarted `mnt-storage.mount`. The old instance lingered as a dead-FUSE shadow mount (busy bind-mounts blocked a clean umount), and the running container kept pointing at it — every `stat` returned `ENOTCONN`. Restarting romm fixed the 502 in seconds. The subsequent attempt to clean up the stacked stale mounts escalated into a full host hang: `umount` of the dead-FUSE entry put the kernel into uninterruptible D-state, dropping theoden off both LAN and tailscale. Recovered via Proxmox `qm stop --skiplock` on rohan; the reboot also accomplished the cleanup. Permanent hardening: `PartOf=mnt-storage.mount` on romm's unit so future mount restarts propagate to the container.

## Timeline

All times CDT (UTC-5).

- **Jul 3 ~14:14** — NixOS deploy on theoden (storage.nix changed in commit `4d2536ff`; generations 101-104 built that afternoon). `switch-to-configuration` restarts the fstab-generated `mnt-storage.mount`.
- **Jul 3 14:16:30** — New mergerfs daemon starts (PID 118578, device `0:141`). The previous instance (device `0:43`) has its daemon exit, but the mount entry cannot be removed — `/srv/nfs` (bind) and romm's container bind-mount hold it busy. `0:43` becomes a dead-FUSE shadow: mount entry present, daemon gone.
- **Jul 3 → Jul 7** — RomM keeps "running" (container PID alive, nginx listening), but its `/romm/library` bind still references dead `0:43`. Any filesystem op on it returns `ENOTCONN`. Gunicorn worker boot fails on every restart attempt; the master keeps the container alive so systemd sees a healthy unit.
- **Jul 7 ~12:38** — User reports RomM login returns a 502 Bad Gateway page from `nginx/1.29.5`.
- **~12:38** — `journalctl -u romm` shows the smoking gun: `OSError: [Errno 107] Socket not connected: '/romm/library'` → `Worker failed to boot`. The nginx in the error is romm's *internal* frontend, not traefik — scope narrows to the container.
- **~12:39** — Container `/proc/self/mountinfo` for `/romm/library` shows backing device `0:43`; host's live mergerfs is `0:141`. The bind-mount pins the dead instance. Diagnosis: stale host-level bind mount from a 4-day-old deploy.
- **12:40** — `systemctl restart romm.service` on theoden. Podman recreates the container, re-bind-mounts the live `0:141`. Library visible, gunicorn boots, HTTP 200. **RomM fixed.**
- **~12:45** — Investigate the lingering stale mounts to prevent recurrence. `/mnt/storage` shows 2 stacked entries; `/srv/nfs` shows 3. Confirmed only one mergerfs process alive (PID 118578) — the bottom entry under `/srv/nfs` is the dead `0:43`.
- **~13:00** — User authorizes a maintenance-window cleanup. Stop `nfs-server` + `romm`, then peel `/srv/nfs`:
  - `umount /srv/nfs` #1 → ok (live `0:141`)
  - `umount /srv/nfs` #2 → ok (live `0:141`)
  - `umount /srv/nfs` #3 → **hangs** (the dead `0:43`; FUSE daemon gone, umount enters D-state)
- **~13:01** — theoden stops responding. LAN ICMP: `Destination Host Unreachable`. Tailscale (`100.64.0.3`): timeout. Host hard-hung.
- **~13:04** — SSH to `root@rohan.lan` (Proxmox host, 192.168.1.24). `qm stop 104 --skiplock` (ACPI shutdown would not work — guest hung) → `qm start 104`. Same recovery playbook as [2026-04-02 rohan-IO-pressure-theoden-hang](2026-04-02-1130-rohan-io-pressure-theoden-hang.md).
- **~13:06** — theoden back up. Mounts clean: single `0:46` on both `/mnt/storage` and `/srv/nfs`. The reboot cleared every stale shadow.
- **~13:07** — Services return: romm, romm-db, romm-redis, nfs-server active. Romm HTTP 200, RQ worker booted. NFS clients reconnect.
- **~13:38** — Deploy hardening (commit `a93f62de`): add `PartOf=mnt-storage.mount` + `After=mnt-storage.mount` to romm's quadlet unit. Verified `systemctl cat romm.service` shows `PartOf=`, romm healthy, mounts still single-instance.

## What Happened

RomM runs on theoden as three podman quadlet containers (`romm`, `romm-db`, `romm-redis`). The `romm` container publishes `8085:8080` and bind-mounts `/mnt/storage/games/library` (a mergerfs pool over three ext4 disks) read-only into the container as `/romm/library`. The pool is also bind-mounted to `/srv/nfs` for NFS export to other LAN hosts.

On Jul 3, a NixOS deploy changed `storage.nix`. `switch-to-configuration` compares the fstab-generated `mnt-storage.mount` unit to the new generation; on a definition change it restarts the unit. Restarting a FUSE mount means a **new daemon and a new superblock** — the old mergerfs instance (`0:43`) was supposed to unmount, but both `/srv/nfs` and romm's container bind-mount held references to it, so the umount failed and `0:43` was left in place as a shadow while `0:141` was mounted on top. The `0:43` daemon exited (its replacement took over), turning `0:43` into a dead-FUSE mount: the kernel mount entry existed, but there was no userspace daemon behind it. Any `stat()`/`readdir()` on a path resolving to `0:43` returned `ENOTCONN` ("Socket not connected", errno 107).

RomM's container had been started Jun 30, so its `/romm/library` bind-mount was pinned to `0:43`. After Jul 3, every gunicorn worker boot tried to stat `/romm/library` during WSGI app load, hit `ENOTCONN`, and exited with code 3. Gunicorn's master kept the container alive (and nginx kept serving), so systemd saw a healthy `romm.service`. The only externally visible symptom was the 502 from romm's internal nginx, which proxies to a backend that no longer existed.

Restarting romm fixed the 502 immediately: podman tore down and recreated the container, re-bind-mounting `/mnt/storage/games/library` against the *current* live `0:141`.

The cleanup that followed was meant to remove the stale `0:43` shadow and the live self-stacked duplicates so the situation couldn't recur. It peeled the live `0:141` entries off `/srv/nfs` without issue, then hit the dead `0:43` at the bottom. `umount` on a FUSE mount whose daemon has already exited does not return `EINVAL` or `EBUSY` — it blocks in uninterruptible (`D`) state waiting on a daemon that will never respond, and under load this wedged the whole VM. Theoden dropped off the network on both interfaces. Recovery was a Proxmox force-reset from rohan; the fresh boot remounted everything single-instance, incidentally achieving the cleanup goal safely.

## Contributing Factors

- **NixOS restarts fstab-generated mount units on definition change.** `switch-to-configuration` restarted `mnt-storage.mount` because `storage.nix` was edited. For a FUSE filesystem, "restart the mount unit" is destructive: it spawns a new daemon and a new superblock, orphaning the old one. There is no NixOS-level opt-out for "don't restart this mount on deploy."
- **Busy bind-mounts block clean umount, leaving dead-FUSE shadows.** `/srv/nfs` and romm's container bind both referenced `0:43`, so the Jul 3 restart could not remove it. The daemon exited but the mount entry stayed — a dead-FUSE shadow that returns `ENOTCONN` on access.
- **Container bind-mounts pin the mount instance at start time.** Podman bind-mounts resolve the source path to a specific superblock when the container starts; they do not follow host remounts. RomM started Jun 30 against `0:43` and never moved to `0:141`.
- **systemd had no signal that romm was broken.** The container PID stayed alive and nginx kept listening, so `romm.service` was `active`. The 502 was the only symptom, and it was user-visible, not monitored.
- **No coupling between `mnt-storage.mount` and its dependent containers.** When the mount unit restarted, nothing propagated to romm, so it kept running against a dead backend.
- **`umount` of a dead-FUSE mount can hang the kernel.** This is what escalated a 2-minute service fix into a 6-minute host outage. The dead `0:43` was reachable only by peeling two live mounts off `/srv/nfs` first, so its danger wasn't visible at the start of the cleanup.
- **Misread of the stacked-mount state.** I initially read the two `/mnt/storage` entries as "two mergerfs instances" and concluded the live duplicates were the only problem. They were actually the *same* live instance self-stacked (`0:141`); the genuinely dead instance (`0:43`) was hiding at the bottom of `/srv/nfs`, not under `/mnt/storage`.

## What I Was Wrong About

- **"The stacked `/mnt/storage` entries are two separate mergerfs instances."** They were the same instance (`0:141`) mounted on itself twice. The dead instance (`0:43`) was not under `/mnt/storage` at all — it lingered under `/srv/nfs`. I peered into the wrong mountpoint first.
- **"Peeling stacked duplicates is safe because both entries are the same live fs."** True for the live `0:141` pair, but I didn't account for the dead `0:43` waiting at the bottom of the `/srv/nfs` stack. Reaching it wedged the host.
- **"A dead FUSE mount can be cleaned up with userspace `umount`."** Wrong. If the FUSE daemon has exited, `umount` can enter uninterruptible D-state. Recovery is a VM reboot, not `umount`.
- **"`BindsTo=` is the right knob to couple romm to the mount."** `BindsTo` is too strong — it stops the unit on any mount deactivation (including transient blips) and doesn't reliably auto-restart on recovery. `PartOf=` is the correct choice: it propagates explicit stop/restart of the mount (exactly the deploy case) without firing on transient failure.
- **"The 502 is probably a romm-internal nginx/backend config issue."** The `nginx/1.29.5` string in the error pointed at romm's own frontend, which was correct, but I initially treated it as an app-level failure. The root cause was a stale host-level bind mount from a deploy four days earlier.

## What Helped

- **The `nginx/1.29.5` signature in the 502 page.** Traefik doesn't identify as nginx, so the error source was unambiguous: romm's internal frontend, meaning the backend behind it was down. This skipped a long ingress-debugging detour.
- **`journalctl -u romm` showed the exact `OSError: [Errno 107] Socket not connected: '/romm/library'`.** The path in the error pointed straight at the bind mount, not the app.
- **Container `/proc/self/mountinfo`.** Comparing the container's backing device (`0:43`) to the host's live device (`0:141`) proved the stale-instance theory in one command.
- **The 2026-04-02 rohan-IO postmortem documented the `qm stop --skiplock` recovery.** When theoden hung, I didn't have to rediscover that `qm reboot` needs guest cooperation and a force stop is required — the prior incident had it.
- **Proxmox host (rohan) stayed reachable.** theoden has no IPMI; if rohan had also been unreachable, recovery would have required physical access.
- **The reboot accomplished the cleanup.** Fresh boot = fresh mounts, no stale shadows. The original cleanup goal was achieved as a side effect of recovery.

## What Could Have Been Worse

- **The dead `0:43` shadow sat latent for four days.** Any other container binding `/mnt/storage` in that window would have hit the same `ENOTCONN`. Only romm binds it directly today, so the blast radius was contained — but a future paperless/arr container binding the pool would have failed identically.
- **NFS clients (`.21`, `.24`, `.26`) were actively connected during the host hang.** The 162KB queued on the `.26` connection suggests an in-flight op. With `hard` mounts (still the default on some clients — see [2026-04-25 forgejo-stale-nfs-mount](2026-04-25-1641-forgejo-stale-nfs-mount.md)), a write in flight during the hang could have stalled indefinitely; soft mounts would have surfaced an error.
- **theoden hosts the k3s control plane.** The ~6 min host outage meant no kubelet heartbeats, no NFS, no Longhorn control plane. If the hang had lasted longer or hit during a CI run, Forgejo Actions and image pulls (zot) would have failed.
- **The stacked-mount state would have accumulated.** Each future `storage.nix` deploy would stack another live instance and leave another dead shadow, increasing the chance of a container binding a stale one. Without the `PartOf` fix, this was a slowly-growing landmine.
- **No monitoring on mount health.** Nothing checked `findmnt -R /mnt/storage` for duplicates, or probed container bind-mounts for `ENOTCONN`. Detection was a user hitting login.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This is the **third** storage/NFS-stale incident in this infrastructure:

- [2026-01-31 git-nfs-mergerfs-permission-denied](2026-01-31-0130-git-nfs-mergerfs-permission-denied.md) — mergerfs semantics surprised an application.
- [2026-04-25 forgejo-stale-nfs-mount](2026-04-25-1641-forgejo-stale-nfs-mount.md) — NFS server reboot left stale mounts that Kubernetes couldn't detect.
- This incident — NixOS mount-unit restart left a stale mergerfs instance that podman couldn't detect.

The common thread: **FUSE/NFS mounts + bind-mounts + a remount event = stale-mount footguns that the consuming layer (podman, kubelet) cannot see.** The consuming process stays "running" while its filesystem is dead.

There is a second, separate pattern worth naming: **troubleshooting actions causing more damage than the original bug.** The romm 502 was a 2-minute fix. The cleanup I ran turned it into a 6-minute host outage. The original incident was contained; the escalation was not. That is a process pattern, not a storage pattern, and it argues for a default of "fix the symptom, document the latent issue, defer risky cleanup to a planned window" rather than cleaning in-band during an active incident.

## Action Items

- [x] Add `PartOf=mnt-storage.mount` + `After=mnt-storage.mount` to romm's quadlet unit (commit `a93f62de`)
- [x] Fix the broken `deploy .#boromir -- --confirm` advice in `AGENTS.md`/`CLAUDE.md` → `--magic-rollback false` (commit `a93f62de`)
- [ ] Apply the same `PartOf`/`After` to any future container that bind-mounts `/mnt/storage` (operational rule; only romm today)
- [ ] Add an operational invariant to `AGENTS.md`: never `umount` a FUSE/mergerfs mount whose daemon has exited — reboot the VM instead
- [x] Add a post-deploy check for stacked/duplicate mounts (`hosts/servers/theoden/storage.nix`): `system.activationScripts.storageMountCheck` runs `findmnt -R` on `/mnt/storage` + `/srv/nfs` on every `switch-to-configuration`, warns to stderr and fires ntfy (`monitoring` topic, priority high) if either has >1 stacked entry. Silent on clean deploys.
- [ ] Investigate whether `mnt-storage.mount` can be made non-restartable on NixOS deploy (e.g. `systemd.services."mnt-storage.mount".unitConfig.RefuseManualStop` or a stable unit hash) — open question, may not be feasible
- [ ] Consider a liveness probe / `ExecStartPost` on romm that `stat`s `/romm/library`, so a stale bind surfaces as a unit failure instead of a silent 502

## Lessons

- **A 502 from an in-container nginx means the container's backend is down.** Check the app's own logs (`journalctl -u romm`) before blaming the ingress. The `nginx/x.y.z` signature tells you *which* nginx.
- **`ENOTCONN` (errno 107) on a directory `stat` = the backing FUSE daemon is gone.** The bind-mount references a dead instance. Restart the container to re-bind the live one.
- **Container bind-mounts pin the mount instance at start time.** They do not follow host remounts. Any remount of a bind-mount source orphans every running container that bound it.
- **NixOS `switch-to-configuration` restarts fstab-generated mount units on definition change.** For FUSE mounts this is destructive (new daemon; old lingers if busy). Editing `storage.nix` is not a no-op for running containers.
- **`umount` of a dead-FUSE mount can hang the kernel.** Recovery is a VM reset, not userspace `umount`. Before peeling a stacked mount, verify each entry's backing daemon is alive — a dead shadow at the bottom will wedge the host when you reach it.
- **`PartOf=` (propagate stop/restart) beats `BindsTo=` (stop on any deactivation) for coupling a container to its backing mount.** `PartOf` fires on the deploy-time restart without firing on transient blips.
- **When troubleshooting goes destructive, own it.** The cleanup caused the outage, not the original bug. "Fix the symptom, defer risky cleanup to a planned window" is the default; in-band cleanup during an active incident is the exception that needs a reason.
- **`qm stop --skiplock <vmid>` on the Proxmox host is the recovery move for a hung theoden.** `qm reboot` needs guest cooperation and will not return. Documented once in 2026-04-02, reused here.
