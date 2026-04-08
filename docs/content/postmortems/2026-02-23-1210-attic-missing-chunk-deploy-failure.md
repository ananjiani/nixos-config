---
date: 2026-02-23
title: Attic orphaned DB record blocked all server deploys
severity: moderate
duration: ~30m
systems: [attic, deploy-rs, theoden]
tags: [storage, binary-cache, deploy, postgres, attic]
commit:
---

## Summary

`deploy .` failed for all servers because the Attic binary cache (`theoden.lan:8080`) returned HTTP 500 for a single NAR path. The NAR's metadata existed in PostgreSQL but the actual chunk file was missing from disk. The database–filesystem inconsistency was invisible to `attic push`, which reported "already cached" and skipped re-uploading.

## Timeline

All times in CST.

- **~12:00** - `deploy .` launched
- **12:10** - Build phase fails: repeated HTTP 500 from `theoden.lan:8080/middle-earth/nar/s8363h07xp5zp46yz3361k7bsv20air9.nar`
- **12:10** - `nixos-system-theoden` fails to build; deploy-rs aborts (checks run before activation)
- **12:12** - HolmesGPT confirms Attic is a NixOS systemd service, not a K8s workload
- **12:13** - `journalctl -u atticd` shows `Storage error: No such file or directory (os error 2)` for every request to that NAR
- **12:15** - Attic config reveals storage at `/srv/nfs/attic` (mergerfs), DB at PostgreSQL
- **12:16** - Confirmed chunk file `fd44bb36-7de0-4959-aac2-bd6017e21a11.chunk` missing from disk
- **12:17** - `attic push` returns "already cached" — DB has the record, suppresses re-upload
- **12:20** - Manually deleted orphaned nar/chunk/object/chunkref DB records
- **12:21** - Re-pushed path; upload succeeded ("pushing 1 path")
- **12:22** - Verified HTTP 200 from `/middle-earth/nar/s8363h07xp5zp46yz3361k7bsv20air9.nar`
- **12:25** - `deploy .` re-run; all nodes (boromir, samwise, theoden, pippin, rivendell) activated and confirmed

## What Happened

A `deploy .` failed during the `nix flake check` phase with repeated HTTP 500 errors from the Attic binary cache. The specific failing path was `checked-attic-server.toml` — Attic's own server configuration file. Because deploy-rs runs `nix flake check` (which builds all derivations) before SSH activation, the missing cache entry prevented even starting any deployment.

Investigation showed atticd was running fine and had ample disk space (5% used on a 10TB mergerfs pool). The error was surgical: one specific NAR was failing with `No such file or directory (os error 2)` in the storage layer. The narinfo endpoint returned HTTP 200 with correct metadata, meaning the PostgreSQL database believed the NAR was valid and complete (`state = 'V'`, `completeness_hint = true`).

Querying the `chunk` table revealed the expected file path (`fd44bb36-7de0-4959-aac2-bd6017e21a11.chunk`) — which did not exist anywhere under `/srv/nfs/attic`. The chunk was recorded with `holders_count = 0`, suggesting it was never fully committed.

Attempting `attic push` to fix it silently did nothing: "1 already cached." Attic's push logic checks the DB, finds the narinfo, and skips uploading — without verifying the chunk file is actually present. The only fix was to delete the four related DB rows (nar, chunk, chunkref, object) and push again, which completed successfully.

## Contributing Factors

- Attic's push is not atomic between DB write and file write — an interrupted push (crash, OOM, transient NFS issue) can leave a DB record in a "valid" state with no corresponding chunk file
- `attic push` deduplication skips upload when the DB narinfo exists, with no filesystem verification
- The HTTP 500 error was opaque from the Nix client side ("some substitutes failed; try --fallback"), giving no hint that the file was physically missing vs. a transient network failure
- deploy-rs running `nix flake check` before activation means a single broken cache path blocks the entire multi-host deployment, even for unrelated hosts
- The affected path happened to be theoden's own config, so it couldn't be served even from itself — there was no fallback path to cache.nixos.org since the path existed in the local nix store

## What I Was Wrong About

- **"HTTP 500 from a cache = service is overloaded or broken"** — the service was healthy; only one specific file was missing. The 500 was a file-not-found surfaced incorrectly as a server error.
- **"`attic push` returning 'already cached' = file is there"** — `attic push` only checks the DB, not the filesystem. "Already cached" is a lie when the DB and disk are out of sync.

## What Helped

- `journalctl -u atticd` immediately showed the exact Rust error (`No such file or directory`) and the exact URI being requested — no ambiguity about which file was missing
- The `narinfo` endpoint still worked, providing the chunk hash and letting us trace the full DB path (nar → chunkref → chunk → remote_file_id)
- The store path existed in theoden's local `/nix/store`, making re-upload trivial (no rebuild needed)
- Only one chunk was corrupted, not a cascade

## What Could Have Been Worse

- If the corrupted path had not been in theoden's local nix store, we'd have had to build it from source (small file, but still)
- If many chunks were corrupted (e.g., after a bad NFS event), this approach would require scripted repair rather than a single push
- If `holders_count` had been non-zero (shared by many NARs), deleting the chunk record would have cascaded to break other paths

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Attic has no built-in integrity verification. Any interrupted push silently leaves the cache in a corrupt state with no observable symptom until someone fetches that specific path. The `holders_count = 0` on affected records is a detectable signal, but nothing acts on it automatically.

## Action Items

- [ ] Write a script that queries PostgreSQL for chunks where `state = 'V'` but the corresponding file is missing from `/srv/nfs/attic`, to use as a periodic health check or pre-deploy gate
- [ ] Add `--fallback` to deploy-rs nix options so Nix builds from source instead of hard-failing when a cache path is unavailable (mitigates impact; doesn't prevent corruption)
- [ ] Document the repair procedure: delete nar/chunk/chunkref/object rows, re-push the store path

## Lessons

- When a binary cache returns HTTP 500, check `journalctl` on the cache host first — the error is often surgical (one missing file) not global
- `attic push` "already cached" does not mean the chunk file exists on disk
- `holders_count = 0` on a `state = 'V'` NAR in the Attic DB is a red flag for an orphaned record
- The narinfo → chunk → remote_file_id query chain in PostgreSQL reliably maps any failing NAR to its expected chunk filename
