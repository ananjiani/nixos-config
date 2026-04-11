---
date: 2026-04-08
title: Zot registry NFS stale file handle breaks all CI jobs
severity: moderate
duration: unknown (detected during investigation, likely days)
systems: [zot, forgejo-runner, nfs, k3s]
tags: [kubernetes, storage, nfs, ci]
commit: pending
---

## Summary

Zot OCI registry returned HTTP 500 on all requests due to a stale NFS file handle on its storage directory. This broke all Forgejo CI jobs because the runner pulls its `ubuntu:act-latest` image through Zot. The pod appeared healthy to Kubernetes (0 restarts, passing liveness probes) despite being completely non-functional. Duration unknown — the stale handle could have persisted for hours or days before being noticed.

## Timeline

- **~??:??** - NFS file handle for `/var/lib/zot` became stale (exact time unknown — no alerting caught it)
- **~19:50** - Noticed CI jobs failing with `not found` when pulling `zot.zot.svc.cluster.local:5000/ghcr.io/catthehacker/ubuntu:act-latest`
- **19:52** - Checked Zot pod — Running, 1/1 Ready, 0 restarts, appeared healthy
- **19:53** - Queried Zot API from debug pod — got HTTP 500 Internal Server Error
- **19:53** - Checked Zot logs — wall of `open /var/lib/zot: stale file handle` errors repeating every ~50ms
- **19:54** - Identified storage: inline NFS volume to `192.168.1.27:/srv/nfs/zot`, mounted as NFSv3
- **19:55** - Confirmed mount options via `ssh samwise mount`: `vers=3`, no `noresvport`
- **19:58** - `kubectl rollout restart deployment/zot -n zot` — pod came back healthy with fresh NFS mount
- **20:00** - Confirmed Zot responding correctly, CI jobs unblocked

## What Happened

Investigating a Forgejo CI failure, the error message said the runner image wasn't found at the Zot registry URL. Initially this looked like a missing image, but querying Zot directly returned HTTP 500 — the registry was broken, not just missing the image.

The Zot logs told the full story: every operation that touched `/var/lib/zot` got `stale file handle`. The storage was an NFS mount to theoden (`192.168.1.27`), defined inline in the Deployment spec. Checking the actual mount options on the node revealed it was using NFSv3 — the Kubernetes default when no mount options are specified.

The pod had been running for 4 days with 0 restarts. Kubernetes thought it was perfectly healthy because the liveness probe hit `/v2/` — the OCI Registry base endpoint that just confirms the HTTP server is running. It never touches storage. So Zot sat there, passing health checks, while returning 500 on every real request.

A simple pod restart fixed the immediate issue by getting a fresh NFS mount. But the underlying problems were: NFSv3's inability to recover from stale handles, and a liveness probe that didn't exercise the storage backend.

Further investigation found three other apps with the same inline NFS pattern: persona-mcp, forgejo (packages volume), and voicemail-receiver. All equally vulnerable.

## Contributing Factors

- **Inline NFS volumes default to NFSv3** — Kubernetes `nfs:` volume specs don't accept mount options, so the kernel negotiated v3 with no resilient options
- **NFSv3 is stateless** — when the server-side file handle is invalidated (server restart, re-export, filesystem change), clients have no recovery mechanism
- **Liveness probe didn't exercise storage** — `/v2/` only checks the HTTP server, not the storage backend. The pod stayed "alive" indefinitely while non-functional
- **No monitoring on Zot error rates** — nothing alerted on the 500s or the log spam
- **Four apps shared the same fragile NFS pattern** — the inline `nfs:` volume was copy-pasted across zot, persona-mcp, forgejo, and voicemail-receiver

## What I Was Wrong About

- **"The pod is Running and Ready, so it must be healthy"** — Kubernetes health is only as good as the probes. A probe that doesn't test the critical path is theater.
- **"NFS just works"** — Inline NFS volumes in Kubernetes give you the worst defaults: NFSv3, no `noresvport`, no `hard` (though `hard` was actually set by default here). The convenience of a 3-line volume spec hides significant fragility.
- **"The liveness probe on `/v2/` is a standard registry health check"** — It is, but it only checks "is the HTTP server alive," not "can the registry actually serve images." For a storage-backed service, liveness must test the storage.

## What Helped

- The error message from the Forgejo runner was specific enough to point at Zot
- Zot's logs were clear and immediate — the `stale file handle` error was obvious
- Being able to `ssh samwise` and inspect the actual NFS mount options confirmed the NFSv3 theory
- A simple pod restart resolved the immediate issue, unblocking CI quickly

## What Could Have Been Worse

- If this had been the forgejo main storage volume (Longhorn) rather than just the packages NFS volume, all of git hosting would have been down
- The stale handle affected only the DedupeTaskGenerator in a tight loop — if Zot had crashed entirely, the liveness probe would have caught it. The partial failure (HTTP server fine, storage broken) was the worst case for detection
- No data was lost — Zot is a pull-through cache, so all images are reconstructable from upstream

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Inline NFS volumes were used in 4 apps, all with the same fragile defaults. This is a systemic issue with how NFS storage was adopted in the cluster — quick to set up but no consideration for failure modes. Any NFS server hiccup on theoden would break all four simultaneously.

More broadly, liveness probes across the cluster may have similar blind spots — testing HTTP connectivity without exercising the actual service path.

## Action Items

- [x] Migrate all 4 NFS volumes from inline `nfs:` to PV/PVC with `nfsvers=4.1`, `hard`, `noresvport`
- [x] Change Zot liveness/readiness probes from `/v2/` to `/v2/_catalog?n=1` (exercises storage)
- [ ] Audit liveness probes across all apps — do they test the critical path or just HTTP? ([#82](https://codeberg.org/ananjiani/infra/issues/82))
- [ ] Add Prometheus alerting for Zot HTTP 5xx error rate ([#83](https://codeberg.org/ananjiani/infra/issues/83))
- [x] Verify theoden NFS server supports NFSv4.1 — confirmed working, paths adjusted for `fsid=0` pseudo-root

## Lessons

- **Inline `nfs:` volumes in Kubernetes are a trap** — they look simple but give you NFSv3 with no mount options. Always use PV/PVC for NFS.
- **Liveness probes must test the critical path** — for a storage-backed service, probe an endpoint that reads from storage. A "hello world" endpoint is not a health check.
- **NFSv4.1 isn't a silver bullet** — it handles server restarts via grace period reclaim, but can't recover if the export path inode changes. It's significantly better than v3, but NFS remains fragile compared to local storage.
- **A Running pod with 0 restarts can be completely broken** — Kubernetes health is defined by probes, nothing more.

## Recurrence — 2026-04-11

It happened again, on `forgejo-packages-nfs` this time.

Symptom: `git push` to `ssh.git.dimensiondoor.xyz` failed after SSH auth succeeded. The forgejo `gitea serv` hook crashed on startup with:

```
[F] Unable to load settings from config: unable to create chunked upload directory:
    /data/packages/tmp (mkdir /data/packages: file exists)
```

The `file exists` error is misleading — the real problem was surfaced by `stat /data/packages` inside the pod, which returned `Stale file handle`. Forgejo's `MkdirAll` stat'd the directory, got EIO from the stale handle, fell back to `mkdir` which returned EEXIST, and bubbled the EEXIST up as a fatal. Same class of failure as the zot incident.

The forgejo deployment pod had been running for 2d4h with 0 restarts, liveness probes passing — invisible to Kubernetes. Web UI worked fine because it doesn't touch `/data/packages` on boot; only git-over-SSH (which shells out to `gitea serv`, which re-reads the config) hit the fatal path. Classic "healthy pod, broken service" pattern.

**Fix**: `kubectl rollout restart deployment/forgejo -n forgejo`. New pod got a fresh NFS mount, `/data/packages` stat'd cleanly, pushes unblocked. ~30s downtime.

**What this tells us about the original action items:**

- **`nfsvers=4.1 + hard` is necessary-but-not-sufficient.** `forgejo-packages-nfs` was migrated to v4.1 as part of this postmortem's action items and still dropped a handle. v4.1's grace period reclaim handles *server restarts*, but can't recover when the export path inode changes underneath (which is what appears to be happening on theoden periodically).
- **`noresvport` was never actually applied.** Action item #1 listed `nfsvers=4.1, hard, noresvport` but only the first two were migrated. All four NFS PVs (`zot-nfs`, `forgejo-packages-nfs`, `persona-mcp-nfs`, `voicemail-nfs`) are missing `noresvport`. Whether `noresvport` would have prevented this specific failure is unclear — it mainly helps with port exhaustion after reconnects — but the action item was marked done while incomplete.
- **The liveness probe audit ([#82](https://codeberg.org/ananjiani/infra/issues/82)) is now more urgent.** Forgejo's probe hits `/api/healthz` which doesn't touch `/data/packages`. A probe that exercised package storage would have caught this within minutes instead of 2d4h.

## Applying `noresvport` doesn't take effect from a rollout restart

While completing the "actually apply noresvport" action item, hit a second, unrelated NFSv4 gotcha worth capturing:

1. Added `noresvport` to all four PVs in `k8s/apps/*/pv.yaml`, committed, pushed, Flux reconciled. Verified with `kubectl get pv forgejo-packages-nfs -o jsonpath='{.spec.mountOptions}'` → `["nfsvers=4.1","hard","noresvport"]`. Looks correct.
2. Rolled out restart on all four deployments (`forgejo`, `zot`, `persona-mcp`, `voicemail-receiver`). All four came up 1/1 Ready with new pods on fresh kubelet-managed NFS mounts.
3. Checked the actual mount on rivendell: `nfsstat -m` and `/proc/mounts` showed zero of 24 NFS entries containing `noresvport`. Not a display quirk — `noresvport` doesn't appear in either output on any of the new mounts.
4. Authoritative test: `ss -tn state established dst 192.168.1.27` on rivendell showed **exactly one** NFS connection, `192.168.1.29:995 → 192.168.1.27:2049`. Source port 995 is a reserved port (<1024). If `noresvport` were in effect the source port would be ≥1024 (ephemeral).

**Root cause**: the kernel NFSv4 client multiplexes all mounts from a single server over a single TCP connection. When kubelet mounts a new NFS volume to `192.168.1.27`, the kernel sees "I already have a connection to that server on source port 995" and reuses it instead of opening a new one. `noresvport` is a *connection creation* option, not a mount creation option — once the TCP connection is established, you can't change its source port. The existing connection was opened the first time any pod on rivendell mounted any volume from theoden, days or weeks ago.

**Implication**: rolling-restarting pods (or even deleting-and-recreating PVs) does not apply `noresvport` on NFSv4. The only ways to actually take a fresh connection are:

1. **Reboot the node.** Cleanest — kills all NFS client state, next mount opens a fresh connection with the current PV mountOptions.
2. **Drain all NFS-consuming pods off the node simultaneously.** Once the last NFS mount is unmounted, the idle connection closes after its timeout. Any subsequent pod rescheduled back onto the node opens a fresh connection. Harder than it sounds because you need every pod with any NFS mount off the node at once, not just pods from one deployment.

Since rebooting k3s nodes for a hygiene improvement isn't worth the disruption, `noresvport` was left in the committed spec and will silently take effect on each node's next planned reboot (NixOS rebuild, kernel update, maintenance window). The PV objects are already correct; nothing else needs to change when the reboot happens.

This is an easy footgun to fall into: the spec looks right, the pods restart cleanly, the cluster reports healthy, and the option simply doesn't apply. The only reliable way to verify `noresvport` is in effect is to check the TCP source port of the NFS connection, not the PV spec, not the kubelet mount output, not the `nfsstat` flags list.

## Reopened / New Action Items

- [x] Apply `noresvport` to all four NFS PVs in the manifests (committed `b1bcaf7`) — **but not yet in effect; see section above**
- [ ] Actually take `noresvport` into effect by rebooting each k3s node on its next maintenance window
- [ ] Add a forgejo liveness probe that exercises `/data/packages` (or change the probe path to one that does)
- [ ] Investigate *why* theoden's NFS exports are invalidating handles — is it a re-export, a filesystem change, ZFS snapshot rollover, kernel upgrade? NFSv4.1 shouldn't drop handles on its own.
- [ ] Evaluate moving `forgejo-packages` off NFS entirely. It's RWO and only mounted by one pod — the only reason it's not on Longhorn is historical. Losing git hosting because of a packages volume stale handle is a bad coupling. ([#83-followup](https://codeberg.org/ananjiani/infra/issues/))
- [ ] Consider whether the "NFS PVC" pattern should exist at all in this cluster, or whether remaining NFS users should migrate to Longhorn.

## Updated Lessons

- **"Migrate to nfs4.1" is a mitigation, not a fix.** Two incidents in three days on the same NFS server prove that v4.1 with `hard` still drops handles under whatever's happening on theoden. The structural answer is either "fix theoden's exports" or "stop using NFS for k8s volumes."
- **Marked-done action items deserve re-verification after a recurrence.** The `noresvport` omission went unnoticed for three days because nobody diffed the live PVs against what the postmortem said was applied. Treat an action item as verified only after confirming the state on the live system, not after the PR merges.
- **PV spec correctness ≠ mount correctness on NFSv4.** The kernel NFS client shares a single TCP connection per (client, server) tuple across all mountpoints, so connection-level options like `noresvport` are locked in at the first mount and can't be changed by any subsequent mount. Verify such options with `ss -tn dst <nfs-server>` and check the source port range, not with `nfsstat -m` or `/proc/mounts`. Rolling-restart deployments won't change these — only a node reboot (or a full drain that closes the last NFS connection) will.
