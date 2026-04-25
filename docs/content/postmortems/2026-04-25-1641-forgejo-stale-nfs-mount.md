---
date: 2026-04-25
title: Forgejo SSH crashes on stale NFS mount after server reboot
severity: moderate
duration: ~5 days (latent), ~30m (active investigation)
systems: [forgejo, rivendell, theoden, nfs, kubernetes]
tags: [storage, nfs, stale-mount, kubernetes, r8169, rivendell]
commit: https://codeberg.org/ananjiani/infra/commit/1a4f944
---

## Summary

Forgejo's SSH git service crashed on every connection because `/data/packages` — an NFS mount for container registry package storage — had gone stale when the NFS server (theoden) rebooted 5 days earlier. The pod itself was `Running` and serving HTTP fine, but any code path touching the stale mount caused an immediate fatal error. Kubernetes had no visibility into the stale mount because the container was still alive. Two other pods (persona-mcp, voicemail-receiver) on the same node had latent stale mounts from the same event. Fix: restarted pods for fresh mounts, then committed permanent hardening via softer mount options and liveness probes that touch the NFS path.

## Timeline

All times CST.

- **Apr 20 ~10:33** — theoden reboots. NFS server restarts with a 90-second grace period for client session reclaim.
- **Apr 20 onwards** — rivendell's NFSv4 client fails to reclaim sessions for some mounts. Stale file handles accumulate silently. Kubernetes pods continue running; the mounts only fail when accessed.
- **Apr 25 ~16:41** — User attempts `git push` to `git@ssh.git.dimensiondoor.xyz`. Connection authenticates but Forgejo crashes immediately with: `Unable to load settings from config: unable to create chunked upload directory: /data/packages/tmp (mkdir /data/packages: file exists)`
- **~16:42** — HolmesGPT investigation shows the Forgejo pod is `Running` with normal HTTP logs, but no errors about the mount.
- **~16:43** — `kubectl exec` into pod: `ls -la /data/` returns `ls: /data/packages: Stale file handle`. The mount is dead from the container's perspective but the pod is still `Running`.
- **~16:44** — Check rivendell host: multiple kubelet NFS subpath mounts are stale. Theoden's journal confirms NFS server reboot on Apr 20. Root cause identified: NFSv4 session reclaim failure after server reboot.
- **~16:45** — Delete Forgejo pod. Kubernetes recreates it with fresh NFS mounts. `/data/packages` is accessible again.
- **~16:46** — SSH test passes: `Hi there, ammar! You've successfully authenticated...`
- **~16:47** — Check other pods on rivendell: persona-mcp and voicemail-receiver also have stale NFS mounts from the same Apr 20 event. Restart both pods.
- **~17:15** — Commit permanent fix: switch all NFS PVs from `hard` to `soft` mounts with fast timeouts; add liveness probes to Forgejo, persona-mcp, and voicemail-receiver that touch the NFS mount path so stale mounts trigger automatic pod restart.

## What Happened

Theoden rebooted on Apr 20. As the NFS server, it offered a 90-second grace period for clients to reclaim their NFSv4 sessions and file handles. Rivendell — which has a known-unstable Realtek r8169 NIC (see [2026-02-13-1400-rivendell-realtek-eee-inbound-drops.md](2026-02-13-1400-rivendell-realtek-eee-inbound-drops.md)) — failed to reclaim some sessions. The existing file handles became invalid, but the kernel mount entries stayed in place. Any filesystem operation on those paths returned `ESTALE` ("Stale file handle").

Kubernetes has no mechanism to detect stale NFS mounts. The Forgejo pod was `1/1 Running`, serving HTTP health checks, and logging normally. The only code path that touched `/data/packages` was the chunked upload directory check during SSH session initialization. When a user connected via SSH for a git push, Forgejo tried to verify `/data/packages/tmp` existed, executed `mkdir /data/packages`, and the syscall returned `EEXIST` wrapped in a misleading error message — `mkdir /data/packages: file exists`. The actual error was `ESTALE`, but Go's `os.Mkdir` surfaces it as `EEXIST` when the parent path resolution fails on a stale mount.

The pod had been in this degraded state for 5 days without anyone noticing because:
- HTTP traffic never touched `/data/packages`
- The pod's existing liveness probe only hit the HTTP port
- `hard` mount options meant any NFS operation would hang forever rather than returning an error
- No monitoring checked for stale mounts on worker nodes

## Contributing Factors

- **NFS server reboot without client session reclaim** — theoden rebooted; rivendell failed to reclaim some NFSv4 sessions within the grace window. This is a known NFSv4 failure mode, especially on networks with marginal stability.
- **rivendell's r8169 NIC instability** — documented in a prior postmortem, this NIC has hardware offloading bugs and driver-level issues with netfilter modifications. Network hiccups during the grace window likely contributed to reclaim failure.
- **`hard` mount options** — All NFS PVs used `hard` mounts, which retry forever on server errors. When a mount goes stale, `hard` means operations hang indefinitely instead of returning an error code that could be detected.
- **No liveness probe touched the mount path** — The Forgejo liveness probe only checked HTTP. The persona-mcp and voicemail-receiver probes checked HTTP but not the NFS-backed filesystem. Kubernetes had no signal that the mount was dead.
- **Misleading error message** — `mkdir /data/packages: file exists` strongly suggests a file/directory type mismatch. It took an `ls` inside the pod to reveal the actual `Stale file handle` error. This delayed correct diagnosis.
- **NFS subpath mounts amplify the problem** — Kubernetes mounts the same NFS export multiple times via subpaths (one per init container + main container). Each subpath is a separate mount point, and any of them can go stale independently.

## What I Was Wrong About

- **"`mkdir /data/packages: file exists` means there's a file instead of a directory"** — This was the obvious interpretation of the error, and it sent the investigation down a wrong path. The actual error was `ESTALE` from a stale NFS mount. Go's `os.Mkdir` maps `ESTALE` to `EEXIST` in some path resolution contexts, producing a confusing message.
- **"The SSH push failure is a client-side or authentication issue"** — The key authenticated successfully, so the problem looked like it might be SSH config or local git setup. The real issue was that the SSH session spawned a Forgejo process that immediately crashed on startup.
- **"Hard mounts are safer because they prevent data loss"** — In a homelab with a single NFS server, `hard` mounts don't provide meaningful safety. When the server is down or the mount is stale, `hard` just causes indefinite hangs that are invisible to Kubernetes probes.
- **"If the pod is Running and HTTP is 200, the service is healthy"** — HTTP health checks only verify the web path. SSH-triggered code paths (like the chunked upload check) can be completely broken while HTTP appears fine.

## What Helped

- **`ssh -T git@host` returned the full Forgejo error** — This immediately shifted the investigation from "SSH/auth problem" to "Forgejo is crashing on startup."
- **`kubectl exec` + `ls -la /data/` showed "Stale file handle"** — The exact kernel error was visible from inside the pod. This was the smoking gun.
- **Theoden's journal had the NFS server reboot logged** — The Apr 20 reboot timestamp lined up perfectly with the timeline. No guessing about when the mount went bad.
- **HolmesGPT had already gathered pod status and logs** — This saved time in the initial fact-gathering phase.
- **Kubernetes pod restart as a quick fix** — Deleting the pod forced a fresh mount. This validated the stale-mount hypothesis immediately.

## What Could Have Been Worse

- **The stale mounts sat latent for 5 days** — If this had been a production system with more users, multiple people would have been unable to push for days before anyone reported it.
- **persona-mcp and voicemail-receiver also had stale mounts** — They hadn't failed yet because their code paths hadn't touched the mounts, but they were one filesystem access away from the same crash. A deployment or config change could have triggered it.
- **zot uses the same NFS server** — Its 100Gi registry storage is on the same NFS export. A stale mount there would break all container image pulls/pushes. Luckily zot runs on boromir, which wasn't affected by this particular reclaim failure.
- **No automated detection** — There was no alert, no metric, no probe that would have caught this. The only detection mechanism was a user trying to push code.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This is the second NFS-related incident in this infrastructure. The prior postmortem ([2026-01-31-0130-git-nfs-mergerfs-permission-denied.md](2026-01-31-0130-git-nfs-mergerfs-permission-denied.md)) also involved NFS behavior surprising an application. The pattern is: NFS's semantics differ from local filesystems in subtle, application-breaking ways, and Kubernetes provides no guardrails for mount health.

More specifically: rivendell + NFS is a recurring risk. The r8169 NIC's instability makes NFSv4 session reclaim unreliable. Any NFS workload scheduled on rivendell has a non-trivial chance of ending up with stale mounts after theoden reboots.

## Action Items

- [x] Switch all NFS PVs from `hard` to `soft` mounts with `timeo=50`, `retrans=2`, and `intr`
- [x] Add liveness probes to Forgejo, persona-mcp, and voicemail-receiver that touch the NFS mount path
- [x] Commit and push changes (commit `1a4f944`)
- [ ] Add node-level monitoring for stale NFS mounts (e.g., a node_exporter textfile collector or a DaemonSet that probes NFS mounts periodically)
- [ ] Consider migrating rivendell's NFS-dependent workloads to Longhorn RWX volumes or local node storage
- [ ] Consider adding a `nodeAffinity` or `taint` to prevent new NFS workloads from scheduling on rivendell until its NIC is replaced or stabilized

## Lessons

- **`ls` inside the pod is the fastest stale-mount detector.** If a filesystem operation returns anything other than a normal listing, you have the answer. Don't trust high-level error messages — the kernel error is authoritative.
- **"mkdir ... file exists" can mean `ESTALE`.** Go (and other runtimes) map `ESTALE` to `EEXIST` in certain path-resolution contexts. Always verify with a direct filesystem check.
- **Hard NFS mounts hide failures.** In Kubernetes, a hanging mount is worse than a failing mount because the pod stays `Running` and probes pass. `soft` mounts let the application (or probe) surface the error.
- **HTTP health checks are insufficient for multi-protocol services.** Forgejo serves HTTP, SSH, and Git. A probe that only checks HTTP misses failures in the other paths.
- **NFSv4 session reclaim is not guaranteed.** Server reboots + marginal networks = stale mounts. Design for that possibility rather than assuming NFS is transparent.
- **rivendell + NFS is a known-risk combination.** The r8169 NIC's documented instability makes it the most likely node to have network issues during critical NFS recovery windows. Factor this into workload placement decisions.
