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
