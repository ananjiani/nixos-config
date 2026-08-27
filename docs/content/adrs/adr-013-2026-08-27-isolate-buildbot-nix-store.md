---
date: 2026-08-27
title: Isolate Buildbot onto a dedicated Nix store daemon
status: accepted
supersedes:
superseded_by:
systems: [theoden, buildbot, nix, attic, k3s]
tags: [ci, storage, nix, isolation]
---

## Context and Problem Statement

Theoden runs k3s/etcd and Buildbot on the same root disk. During the 2026-08-24 outage, `nix-eval-jobs` filled and saturated that disk, which starved etcd and caused cluster services to fail. Later canaries still caused etcd delays up to 30 seconds, even with one Nix job, write limits, and k3s I/O priority. Moving only Nix build scratch to `/mnt/disk1` did not help because store reads caused failures before scratch writes began. `/mnt/disk1` is a separate ext4 disk with 1.7 TiB free.

## Decision Drivers

- Keep k3s/etcd and Comin on the host `/nix/store` even while CI is building
- Stop Buildbot from filling the root disk
- Reuse the spare physical disk already mounted at `/mnt/disk1`
- Avoid a new CI machine or a store migration that rewrites the host
- Keep a live canary so the blocked worker does not start on deploy

## Considered Options

1. **Dedicated Nix daemon and chroot store on `/mnt/disk1`** (chosen)
2. **Move host `/nix` onto `/mnt/disk1`**
3. **Move k3s/etcd off the root disk**
4. **Dedicated CI host**

## Decision Outcome

Chosen option: **dedicated Nix daemon and chroot store on `/mnt/disk1`**, because Nix 2.34.7 already supports a second root daemon (`nix daemon --store /mnt/disk1/buildbot-nix` plus a separate `NIX_DAEMON_SOCKET_PATH`) and Buildbot worker children inherit `NIX_REMOTE`. Host Nix and Comin keep the default socket and `/nix/store`.

Theoden runs `buildbot-nix-daemon` as root against `/mnt/disk1/buildbot-nix`, with scratch outside that chroot at `/mnt/disk1/buildbot-nix-build`. The scratch directory is `0700 root:root`; putting it inside the chroot makes sandbox build directories root-owned and breaks builders. The daemon uses `max-jobs=1`, `cores=2`, and one `nixbld-ci` build user so CI does not share the host `nixbld` uid lock. The Buildbot worker and `attic-watch-store` set `NIX_REMOTE=unix:///mnt/disk1/buildbot-nix/nix/var/nix/daemon-socket/socket`. Attic still parses Nix paths from the logical `/nix/store`, but upstream `watch-store` inotify-watches that logical dir, not the chroot on disk1. Theoden patches Attic so `ATTIC_WATCH_STORE_PATH` points at `/mnt/disk1/buildbot-nix/nix/store` and remaps each lock-file basename onto the logical store dir before `parse_store_path`. The patched client defaults to one upload job. `nix-eval-jobs` 2.34.1 `queryOutputs` always opens the logical drv path on the host filesystem, so a UDS remote/chroot store fails after instantiate. Theoden patches it to query output names without local drv files on remote stores and to report `cacheStatus=notBuilt` so the dedicated daemon performs substitution/build. Worker, daemon, and Attic share `buildbot-ci.slice` at 3 CPUs and 10G so CI cannot take all 4 host cores; k3s keeps the remaining CPU. Individual unit quotas stay in place. The master stays off that slice. Buildbot keeps its direct GC-root links under the host `/nix/var/nix/gcroots`, while garbage collection talks to the dedicated daemon. GC runs by hand only while the worker is stopped because `nix-eval-jobs` cannot root queued derivations through a daemon store. The rollout used `/run/allow-buildbot-worker` as a temporary canary gate; the gate was removed after the full PR build passed.

### Consequences

- Good: CI store growth lands on disk1. Root disk stays for k3s, etcd, and Comin.
- Good: Host `nix.settings` and the default `nix-daemon` stay unchanged.
- Good: A missing disk1 mount stops the CI daemon and worker instead of falling back to the root disk.
- Good: Shared `buildbot-ci.slice` caps worker + daemon + Attic at 3 CPUs / 10G and leaves one CPU for host/k3s.
- Good: Attic watches the physical dedicated store and remaps lock files to logical `/nix/store` paths.
- Bad: Theoden now runs two Nix daemons, two stores, and a second build-user group.
- Bad: `attic-watch-store` on Theoden watches the CI store only. Host-store paths are no longer pushed from this unit.
- Bad: First CI builds miss the host store and refill the dedicated store from Attic or source.
- Bad: Store GC is a manual maintenance step that requires a stopped worker.
- Bad: Theoden runs a patched `attic-client` until upstream accepts a watch-path override.
- Bad: Theoden runs a patched `nix-eval-jobs` 2.34.1 because `queryOutputs` assumes the drv is on the host filesystem. Remote attrs report `notBuilt` so the dedicated daemon performs actual cache substitution/build.
- Neutral: `max-jobs=1` is a capacity cap, not a store property. Raise jobs only with more `nixbld-ci` users.

### Confirmation

- `buildbot-nix-daemon.service`, `buildbot-worker.service`, and `attic-watch-store.service` start automatically when disk1 is mounted.
- One eval/build writes store paths under `/mnt/disk1/buildbot-nix/nix/store` and scratch under `/mnt/disk1/buildbot-nix-build`, not the host `/nix/store`.
- Host Comin/`nix-daemon` keep using `/nix/store`. Root disk usage does not jump during that build.
- `attic-watch-store` has `NIX_REMOTE`, `ATTIC_WATCH_STORE_PATH=/mnt/disk1/buildbot-nix/nix/store`, the patched client, one default upload job, and `Slice=buildbot-ci.slice`. Do not treat eval as live proof until a canary store path is pushed.
- Worker and daemon are also in `buildbot-ci.slice`. Slice quota is CPUQuota=300% / MemoryMax=10G. Master is not in that slice.
- The exact PR canary completed all 16 child requests with no k3s restart, node `NotReady`, readyz failure, etcd operation above 5 seconds, or OOM.
- `nix-eval-jobs --check-cache-status` against the dedicated store returned 16 success records and no error records in 222 seconds.

## Pros and Cons of the Options

### Dedicated Nix daemon and chroot store on `/mnt/disk1`

- Good: Isolates CI writes without moving the host store or the cluster.
- Good: Uses a Nix 2.34.7 feature instead of bind-mounts or a second machine.
- Good: Worker, `nix-eval-jobs`, and Attic inherit one `NIX_REMOTE` value.
- Good: Physical watch override plus basename remapping makes Attic see the chroot store without changing Nix's logical store dir.
- Good: Shared slice plus one Attic upload job keep CI off the last host CPU.
- Bad: Two daemons and manual store GC add operating steps.
- Bad: Attic watch on Theoden no longer covers the host store.
- Bad: Theoden carries an Attic client patch until upstream grows a watch-path override.
- Bad: Theoden carries a `nix-eval-jobs` patch until upstream stops opening local drv files on remote stores.

### Move host `/nix` onto `/mnt/disk1`

- Good: One daemon, one store, no `NIX_REMOTE` split.
- Bad: Comin, k3s activations, and CI still share one store and one disk-full failure domain.
- Bad: Migrating a live `/nix` on the k3s node is a high-risk cutover.

### Move k3s/etcd off the root disk

- Good: Cluster state would survive a CI fill of `/nix/store`.
- Bad: Buildbot would still fill the root disk and break Comin, SSH, and the host.
- Bad: etcd/Longhorn data-path surgery on the live node is larger than a second Nix daemon.

### Dedicated CI host

- Good: Cleanest isolation. No shared disk, daemon, or cgroup with k3s.
- Bad: New machine, secrets, Comin, and worker wiring for a problem disk1 already solves.
- Neutral: Revisit if disk1 IO or Theoden RAM becomes the limit.
