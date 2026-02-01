---
date: 2026-02-01
title: Flux git clone failures due to HTTP/2 over Flannel VXLAN
severity: major
duration: ~2h
systems: [flux, k3s, flannel, source-controller]
tags: [kubernetes, networking, mtu, http2, vxlan, flannel]
commit: https://codeberg.org/ananjiani/infra/commit/9ce910c1
---

## Summary

Flux source-controller could not clone the GitRepository from any HTTPS git remote (Codeberg or GitHub), causing all Flux reconciliation to stall. The issue was that HTTP/2 connections from pods silently fail over Flannel VXLAN when the pod MTU leaves insufficient headroom within the physical network's 1500-byte MTU. Lowering the host interface MTU from 1500 to 1450 (yielding pod MTU of 1400 instead of 1450) resolved it.

## Timeline

All times CST.

- **~Jan 31 18:00** - Flux source-controller starts failing to clone from Codeberg with "context deadline exceeded." The exact onset time is unknown; it was discovered during an unrelated persona-mcp debugging session.
- **Jan 31 18:47** - Switched GitRepository URL from Codeberg to GitHub mirror (`cfbe1cf`), assuming Codeberg was unreachable. Clone still fails.
- **Feb 01 01:50** - While debugging persona-mcp's virtual key error, noticed Flux was still stuck. GitHub mirror URL had a case mismatch (`NixOS-config` vs `nixos-config`). Fixed in `1f90e90`.
- **Feb 01 02:00** - Case-fixed URL still fails. Source-controller repeatedly times out after 5 minutes. Began deeper investigation.
- **Feb 01 02:30** - Tested `git clone` from a pod using the `alpine/git` image. Failed immediately with `HTTP/2 stream 5 was not closed cleanly: CANCEL (err 8)`.
- **Feb 01 02:35** - Forced `git config --global http.version HTTP/1.1` and retried. Clone succeeded instantly. Root cause identified: HTTP/2 is broken over VXLAN.
- **Feb 01 02:40** - Confirmed same failure on samwise node. Cluster-wide issue.
- **Feb 01 03:00** - Attempted `GODEBUG=http2client=0` on source-controller. No effect (go-git doesn't use Go's default HTTP transport path affected by this flag).
- **Feb 01 03:30** - Lowered host MTU to 1450 on all nodes and updated `FLANNEL_MTU` in subnet.env. Mixed MTU state (old pods at 1450, new at 1400) caused all pod networking to break worse.
- **Feb 01 03:55** - Rolling restart of k3s on all three nodes (boromir, samwise, theoden) one at a time to get a clean MTU state.
- **Feb 01 04:10** - All nodes back with `FLANNEL_MTU=1400`. Triggered Flux reconcile.
- **Feb 01 04:12** - Flux successfully cloned and stored artifact at `9ce910c1`. Confirmed resolved.

## What Happened

The Flux source-controller uses go-git to clone the GitRepository over HTTPS. Go's HTTP client negotiates HTTP/2 with servers that support it (GitHub, Codeberg). HTTP/2 uses binary framing with multiplexed streams over a single TLS connection.

Flannel VXLAN encapsulates pod traffic in a 50-byte outer header. With the physical network MTU at 1500, flannel auto-detected the pod MTU as 1450 (1500 - 50). This left zero headroom. HTTP/2's framing overhead, combined with TLS record headers and TCP options, caused certain packets to exceed what the VXLAN tunnel could carry without fragmentation issues. The result was HTTP/2 stream cancellations or silent connection hangs.

HTTP/1.1 uses simpler framing with less overhead per request, which fit within the available MTU. This is why `wget` (HTTP/1.1) and `git clone` with `http.version=HTTP/1.1` always worked, while the default HTTP/2 path failed.

The initial attempt to switch from Codeberg to GitHub was a red herring — both remotes failed identically because the issue was in the pod network, not the remote server.

The mid-session attempt to hot-patch the MTU (changing `cni0`, `subnet.env`, and `ens18` without restarting k3s) created a worse situation: mixed MTU values across the bridge, veth interfaces, and VXLAN tunnel caused all pod networking to degrade. A clean k3s restart on each node was required to get a consistent MTU across all interfaces.

## Contributing Factors

- **Flannel VXLAN auto-detects MTU with zero safety margin.** Given a 1500-byte host interface, flannel sets pod MTU to exactly 1450 (1500 - 50 VXLAN overhead). This is technically correct for the encapsulation math but leaves no room for protocol-level overhead like HTTP/2 framing.
- **HTTP/2 is the default for HTTPS in modern stacks.** Both Go's `net/http` and `libcurl` negotiate HTTP/2 via TLS ALPN by default. There's no cluster-wide way to force HTTP/1.1.
- **go-git's failure mode is a silent 5-minute hang.** Unlike `curl`/real `git` which immediately report `HTTP/2 stream was not closed cleanly`, go-git just hangs until the context deadline. This made the issue look like a connectivity problem rather than a protocol problem.
- **No monitoring for Flux source reconciliation failures.** The GitRepository had been failing for an unknown period before it was noticed during unrelated debugging.

## What I Was Wrong About

- **"Codeberg is unreachable from pods"** - The initial assumption was that Codeberg was down or DNS-blocked. The switch to GitHub was based on this incorrect diagnosis. Both remotes had the same HTTP/2 problem.
- **"GODEBUG=http2client=0 will force HTTP/1.1 in go-git"** - This Go runtime flag only affects `http.Transport` when `ForceAttemptHTTP2` is not set. go-git's transport setup bypasses this, so the flag had no effect.
- **"Hot-patching MTU on running interfaces will fix pods"** - Changing `cni0` and `subnet.env` while k3s was running created an inconsistent state where old veths (1450) were attached to the bridge (1400), and the VXLAN tunnel (1450) didn't match the new pod MTU (1400). This made things worse, not better. A full k3s restart was needed for a clean slate.
- **"MTU 1450 is fine because the encapsulation math works out"** - Technically 1450 + 50 = 1500, which fits the physical MTU. But this ignores that protocols like HTTP/2 add additional overhead within the TCP payload that can interact badly with the exact-fit MTU boundary.

## What Helped

- **The `alpine/git` test pod approach.** Being able to spin up ephemeral pods with a real `git` binary was the key to isolating HTTP/2 as the cause. Real git gave clear error messages (`HTTP/2 stream 5 was not closed cleanly`) while go-git was silently hanging.
- **`wget` working consistently.** The fact that `wget` (HTTP/1.1 only) always worked was the contrast that pointed to HTTP/2 as the differentiator.
- **The flannel-backup/restore systemd services.** These (added in a previous incident) ensured the flannel subnet.env was properly managed across the k3s restarts. Without them, the restarts could have caused a repeat of the flannel-subnet-env-reboot incident.

## What Could Have Been Worse

- **The mid-flight MTU patching could have caused data loss.** Mixed MTU across the bridge/veth/tunnel interfaces broke pod networking for all workloads. If pods with persistent connections (databases, etc.) had been affected more severely, there could have been corruption or data loss. The rolling k3s restart fixed it, but the window of broken networking was risky.
- **If k3s restarts had failed to regenerate flannel state.** This was a previous incident pattern. The flannel backup services mitigated this.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This is the third MTU-related incident in this cluster (after the Docker-in-Docker registry push failures and the general Flannel VXLAN setup). The common thread: Flannel VXLAN with auto-detected MTU leaves no safety margin, and different workloads hit the boundary in different ways.

The underlying issue is that VXLAN encapsulation on a standard 1500-byte network is fundamentally tight. Every new protocol or workload that adds framing overhead (HTTP/2, Docker-in-Docker, etc.) risks hitting the MTU wall. The fix applied here (lowering host MTU to 1450 so pods get 1400) provides a 100-byte safety margin, which should handle most cases. But the pattern suggests that jumbo frames on the physical network or switching from VXLAN to a non-encapsulating backend (like `host-gw`) would be more robust long-term solutions.

## Action Items

- [x] Lower host interface MTU to 1450 via systemd oneshot before k3s starts (`9ce910c1`)
- [x] Rolling restart all k3s nodes to apply clean MTU
- [x] Delete stale flannel-subnet.env backups with old MTU values
- [ ] Add Flux source reconciliation failure alerting (e.g., Prometheus alert on `gotk_reconcile_condition{type="Ready",status="False"}`)
- [ ] Deploy the NixOS config change via deploy-rs to make the MTU fix persist across reboots (currently only applied via k3s restart, not a NixOS rebuild)
- [ ] Evaluate switching flannel backend from `vxlan` to `host-gw` since all nodes are on the same L2 subnet, eliminating VXLAN overhead entirely

## Lessons

- **When pods can wget but not git clone, suspect HTTP/2 over VXLAN.** The telltale sign is that simple HTTP/1.1 operations work but anything that negotiates HTTP/2 fails or hangs.
- **Never hot-patch MTU on a running CNI.** The bridge, veths, VXLAN tunnel, and `subnet.env` all need to agree. Change the host MTU and restart k3s for a clean state.
- **go-git's failure mode is a silent hang, not an error.** When debugging Flux source-controller clone failures, test with a real `git` binary in a pod first — it gives much better error messages.
- **"Flannel MTU = host MTU - 50" is necessary but not sufficient.** Protocols like HTTP/2 add their own overhead within the payload. Budget at least 100 bytes of headroom, not just the bare VXLAN overhead.
