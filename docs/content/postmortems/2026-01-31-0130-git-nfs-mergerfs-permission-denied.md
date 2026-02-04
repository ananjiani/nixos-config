---
date: 2026-01-31
title: Git commits fail on NFS-exported mergerfs with Permission Denied
severity: moderate
duration: 2h 30m
systems: [theoden, boromir, ammars-pc, mergerfs, nfs]
tags: [storage, nfs, mergerfs, fuse, git, deploy-rs]
commit:
---

## Summary

Git commits on NFS-mounted repositories stored on theoden's mergerfs pool failed with "Permission denied" errors. The investigation uncovered a chain of interacting issues across mergerfs FUSE permissions, NFSv3/v4 protocol behavior, and the Linux kernel's nfsd code path. Direct access on the server was fixed, but git over NFS remains fundamentally broken due to how nfsd handles file creation with restrictive modes. Two deploy-rs rollbacks occurred as side effects of attempted fixes.

## Timeline

All times CST.

- **~23:00** - User reports inability to commit in `/mnt/nfs/persona-mcp/keres`
- **23:05** - Initial investigation: `.git/objects/` directories owned by root with no group write on disk2 (mergerfs branch). `chown`/`chmod` via NFS client had no effect due to `root_squash`... except the server had `no_root_squash`. The real issue: mergerfs `func.chown=ff` applied changes to disk1 (first found), but `func.getattr=newest` read attributes from disk2 (newer timestamps). Changes appeared to not take effect.
- **23:20** - Fixed permissions directly on disk2 via SSH to theoden. Still failed.
- **23:30** - `strace` revealed the actual failure: `openat(".git/objects/05/tmp_obj_xxx", O_RDWR|O_CREAT|O_EXCL, 0444)` succeeded, `write()` succeeded, but `close()` returned `EACCES`. NFSv3 re-checks permissions on flush — file is `0444` (no write), so the server rejects the writeback.
- **23:35** - Attempted `core.sharedRepository=group` and `0664` — git hardcodes `0444` for temp object files regardless of config.
- **23:40** - Switched NFS client to NFSv4.2 (`nfsvers=4.2` in nfs-client.nix). NFSv4 should track open state server-side. But with NFSv4 the `openat()` itself failed — `default_permissions` on the mergerfs FUSE mount rejected `O_RDWR` on a `0444` file at the FUSE layer.
- **23:45** - First deploy-rs rollback: boromir failed because `mnt-nfs.automount` doesn't support `reload` (only `restart`), and NixOS activation tried to reload it.
- **23:55** - Identified `kernel-permissions-check=false` as the mergerfs option to disable FUSE-layer permission checks (`default_permissions`). Added it to storage.nix along with `inodecalc=path-hash` for stable NFS inodes.
- **00:10** - Second deploy-rs rollback: theoden failed because `mnt-storage.mount` (FUSE/mergerfs) also can't be reloaded with changed options — requires full unmount/remount.
- **00:15** - Rewrote nfs-client.nix to use explicit `systemd.mounts`/`systemd.automounts` instead of `fileSystems` with `x-systemd.automount`, avoiding the automount reload issue.
- **01:00** - Used `nixos-rebuild boot` + reboot on theoden and boromir. Changes applied successfully.
- **01:10** - Git commit confirmed working directly on theoden via SSH (`su ammar`).
- **01:25** - Git commit over NFS from desktop still fails. `strace` shows same `openat(..., 0444) = -1 EACCES`. The nfsd kernel code path creates the file then opens it in two separate steps — unlike local `open(O_CREAT|O_RDWR)` which skips the permission check on newly created files. This is a kernel-level limitation that can't be configured around.
- **01:30** - Accepted that git commits over NFS to mergerfs-backed storage is a known incompatibility. Commits work via SSH to the server.

## What Happened

A persona-mcp git repository on theoden's NFS-exported mergerfs pool couldn't accept commits from NFS clients. Git creates loose object temp files with hardcoded mode `0444` (read-only) and writes to them through the already-open file descriptor. On a local filesystem this works because the kernel's `path_openat()` code path skips the permission check on files it just created. NFS doesn't have this optimization — nfsd creates the file and opens it as two separate operations, and the open checks the file's `0444` mode against the requested `O_RDWR` access, which fails.

The investigation was complicated by multiple interacting layers: mergerfs's `default_permissions` FUSE option added an extra permission check that blocked even NFSv4 (which would have otherwise tracked open state correctly), mergerfs's `func.chown=ff` + `func.getattr=newest` policy made permission fixes appear to not take effect (changes applied to one disk branch but reads came from another), and NixOS's activation scripts can't reload automount or FUSE mount units, causing deploy-rs rollbacks when mount options changed.

## Contributing Factors

- **Git hardcodes `0444` for loose object temp files** — `create_tmpfile()` in `object-file.c` uses mode `0444` and `core.sharedRepository` only affects the final rename, not the temp file creation.
- **nfsd creates and opens files in two steps** — Unlike the local VFS `path_openat()` which atomically creates+opens and skips permission checks on new files, nfsd calls `vfs_create()` then `dentry_open()` separately, and `dentry_open()` checks the file's `0444` mode.
- **mergerfs enables `default_permissions` by default** — This added a FUSE-layer permission check that blocked even NFSv4's stateful OPEN, compounding the nfsd issue.
- **mergerfs `ff` (first-found) policy for writes vs `newest` for reads** — `chown`/`chmod` applied to disk1 but `getattr` read from disk2 (newer timestamps), making fixes appear ineffective and masking the real problem.
- **NixOS can't reload automount/FUSE mount units** — `systemctl reload` isn't supported for automount units, and FUSE mounts can't be remounted with changed options. Both caused deploy-rs rollbacks.
- **Initial `git add` was run as root** — Created object directories owned by root on one mergerfs branch, adding a permissions layer on top of the fundamental protocol issue.

## What I Was Wrong About

- **"NFSv4 will fix it because it has stateful OPEN"** — True in theory, but mergerfs's `default_permissions` blocked the OPEN at the FUSE layer before nfsd could establish state. And even after disabling that, nfsd's own code path still checks permissions separately from the create.
- **"`chown`/`chmod` on the NFS server will fix the root-owned directories"** — The commands appeared to succeed but changes went to disk1 (`func.chown=ff`) while reads came from disk2 (`func.getattr=newest`). The mergerfs policy interaction wasn't obvious.
- **"Changing mount options can be applied live via deploy-rs"** — FUSE and automount units can't be reloaded or remounted during NixOS activation. Mount option changes require a reboot.
- **"The permission issue is in the FUSE/NFS configuration layer"** — It's actually in the kernel's nfsd code path, which is not configurable.

## What Helped

- `strace` on `git commit` immediately revealed the exact failing syscall and mode, cutting through layers of abstraction
- SSH access to theoden allowed testing directly on the server, confirming the issue was NFS-specific (not mergerfs-specific)
- The mergerfs documentation had the `kernel-permissions-check` option documented (maps to FUSE `default_permissions`)
- deploy-rs magic rollback prevented broken configurations from persisting on servers

## What Could Have Been Worse

- The duplicate data on disk1/disk2 with inconsistent ownership could have caused data corruption if both branches were written to simultaneously with different content
- If the NFS mount had been used for more critical services (not just persona-mcp), the stale file handles after theoden's reboot (inode change from `inodecalc=path-hash`) could have caused wider disruption
- The deploy-rs rollbacks protected against leaving servers in a partially-configured state with non-functional mounts

## Is This a Pattern?

- [x] Pattern: Revisit the approach

NFS + mergerfs + git is fundamentally incompatible due to how nfsd handles file creation permissions. This isn't a configuration issue — it's a kernel code path limitation. Any future service that creates files with restrictive modes and writes through the fd will hit the same problem over NFS.

More broadly: layering network filesystems (NFS) on top of union filesystems (mergerfs) on top of FUSE creates a deep stack where each layer has its own permission model, and the interactions between them are non-obvious and often not configurable.

## Action Items

- [x] Set `kernel-permissions-check=false` on mergerfs (fixes direct server access)
- [x] Add `inodecalc=path-hash` for stable NFS inodes
- [x] Switch NFS clients to NFSv4.2
- [x] Replace `fileSystems` + `x-systemd.automount` with explicit `systemd.mounts`/`systemd.automounts` to avoid deploy-rs rollbacks
- [ ] Clean up duplicate data across disk1/disk2 in the mergerfs pool (the keres `.git/objects` exist on both branches with inconsistent state)
- [ ] Consider changing mergerfs `func.chown` and `func.chmod` from `ff` to `all` so permission changes apply to all branches consistently
- [ ] For repos that need git commits, commit via SSH to theoden rather than over NFS

## Lessons

- **`strace` first, theorize second.** The exact syscall, mode, and errno told the whole story — everything else was working backwards from there.
- **mergerfs policy interactions are subtle.** `func.chown=ff` + `func.getattr=newest` means you can `chown` a file and then `ls` shows the old owner. Always check the underlying disks directly when debugging mergerfs permission issues.
- **NFS mount option changes require reboots.** Don't try to deploy mount option changes through deploy-rs or `nixos-rebuild switch` — use `nixos-rebuild boot` + reboot.
- **nfsd's create+open is two steps, not one.** The local kernel VFS optimizes `O_CREAT|O_RDWR` to skip permission checks on newly created files. nfsd doesn't have this optimization. Any application that creates restrictive-mode files and writes through the fd will break over NFS.
- **Git's `0444` object mode is hardcoded and not configurable.** `core.sharedRepository` only affects the final file after rename, not the temp file creation.
