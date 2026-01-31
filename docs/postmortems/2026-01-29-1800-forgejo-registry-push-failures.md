---
date: 2026-01-29
title: Forgejo container registry push failures - five cascading issues
severity: major
duration: ~20h (intermittent across multiple debugging sessions)
systems: [forgejo, forgejo-runner, traefik, opnsense, k3s, zot, nfs]
tags: [kubernetes, networking, vpn, mtu, storage, registry, oom]
commit: https://codeberg.org/ananjiani/infra/commit/1db85a7
---

## Summary

Pushing a container image from a Forgejo CI runner to the Forgejo package registry failed repeatedly over ~20 hours. What appeared to be a single problem was actually five independent issues stacked on top of each other, each revealed only after the previous one was resolved. Ultimately abandoned Forgejo's built-in registry in favor of Zot, which is purpose-built for OCI image storage.

## Timeline

All times CST.

- **~18:00 Jan 28** - CI job fails: `Failed to connect to code.forgejo.org port 443` - runner can't clone the checkout action
- **~18:15** - Diagnosed as Mullvad VPN blocking Hetzner IPs. Added `code.forgejo.org` to VPN exempt destinations in OPNsense. Confirmed fix
- **~18:30** - CI job fails again: `connection reset by peer` during blob PATCH upload
- **~18:40** - Discovered MTU mismatch: pod eth0 = 1450, docker bridge inside dind = 1500. Set `"mtu": 1400` in dind daemon.json
- **~19:00** - CI job fails: `504 Gateway Timeout` after exactly 60000ms on blob PATCH
- **~19:10** - Added `ServersTransport` with 600s `responseHeaderTimeout` for Forgejo IngressRoute
- **~19:30** - CI job fails: `connection reset by peer` again during PATCH
- **~19:40** - Identified Traefik's entrypoint `readTimeout` (default 60s) as the actual client-side timeout. Increased to 600s
- **~20:00** - CI job fails: `500 Internal Server Error` - `mkdir /data/packages/6e: permission denied`
- **~20:05** - NFS packages directory owned by `root:storage(1500)`, Forgejo runs as `git(1000:1000)`. Fixed with `chown 1000:1000`
- **~20:15** - CI job fails: `no such host` DNS failure for `git.dimensiondoor.xyz` mid-upload. Added `--add-host` to runner container options
- **~20:30** - CI job appears to hang. Blob upload proceeds at near-zero throughput for 10+ hours
- **~06:30 Jan 29** - Identified Docker bridge networking as the bottleneck: traffic hairpins from dind bridge (172.17.0.0/16) through NAT, out the pod, through LoadBalancer, back into the cluster. Switched runner job containers to `network: host`
- **~11:30** - Discovered stale temp files from failed uploads filled the 10Gi Longhorn PVC (9.7GB in `/data/tmp/package-upload/`). Forgejo crashes with `database or disk is full`. Cleaned up temp files, moved `CHUNKED_UPLOAD_PATH` to NFS
- **~19:00** - CI job fails: `502 Bad Gateway`. Forgejo pod OOMKilled (1Gi limit) while finalizing a multi-GB blob upload
- **~19:15** - Decided to abandon Forgejo's registry entirely. Wired up Zot as the internal container registry: containerd registries.yaml, dind insecure-registries, deployed to all k3s nodes

## What Happened

A CI workflow needed to build and push a container image to the Forgejo package registry. The image contained a large layer (~500MB-4.5GB blob), and the push path traversed an unusually deep network stack: job container → Docker bridge → dind pod → k8s overlay → LAN → OPNsense VPN routing → LoadBalancer hairpin → Traefik TLS termination → Forgejo → NFS.

Each layer of this stack had its own failure mode, and fixing one only revealed the next. The issues were:

1. **VPN routing**: OPNsense routes all LAN traffic through Mullvad VPN. Hetzner (hosting code.forgejo.org) was unreachable through the Mullvad exit IP.

2. **MTU mismatch**: Docker bridge inside dind defaulted to MTU 1500, but the k8s pod network uses MTU 1450 (VXLAN overhead). Packets >1450 bytes were silently dropped.

3. **Traefik timeouts**: Both the `ServersTransport` responseHeaderTimeout (backend side) and the entrypoint `readTimeout` (client side) defaulted to 60 seconds. A multi-hundred-MB blob upload takes longer than that.

4. **NFS permissions**: The packages directory on NFS was owned by `root:storage(1500)` while Forgejo runs as `git(1000:1000)`. Write access denied.

5. **DNS expiry**: Long uploads caused DNS cache entries to expire mid-transfer, resulting in transient `no such host` failures.

6. **Docker bridge throughput**: The Docker bridge network inside dind added NAT overhead and forced traffic through a LoadBalancer hairpin path, reducing throughput to near-zero for large transfers.

7. **Disk pressure**: Failed upload attempts left multi-GB temp files on the 10Gi Longhorn PVC, eventually filling it and crashing Forgejo (SQLite "database or disk is full").

8. **OOM on finalization**: Forgejo reads the entire blob into memory during the PUT finalization step to verify the SHA256 digest. A multi-GB blob exceeded the 1Gi memory limit, causing OOMKill.

## Contributing Factors

- **Deep network stack**: Job containers inside Docker-in-Docker inside k8s pods, with VPN policy routing and LoadBalancer hairpin, meant every layer could independently fail
- **Forgejo's registry implementation buffers blobs in memory** during finalization rather than streaming the digest computation
- **Forgejo's default temp path** (`/data/tmp/package-upload/`) shares the main data volume instead of using dedicated storage
- **No monitoring on PVC utilization** - the disk filled silently
- **OPNsense VPN policy routing is invisible** - traffic to certain IPs silently goes through VPN with no indication why connectivity fails
- **Default timeouts everywhere** - Traefik's 60s defaults are reasonable for web requests but catastrophic for registry uploads
- **NFS mount permissions were set up for a different user context** than the one Forgejo runs as in k8s

## What I Was Wrong About

- **Assumed a single root cause** - Each fix revealed a new, unrelated failure. The instinct to think "this should fix it" was wrong five times in a row
- **Assumed Docker bridge networking was fine for CI** - Bridge networking inside dind adds NAT, MTU issues, and DNS complications. Host networking is the correct choice for dind-based runners
- **Assumed Forgejo's registry could handle large blobs** - It reads them into memory during finalization, making it fundamentally unsuitable for large container images without proportionally large memory limits
- **Assumed the upload temp path was on adequate storage** - The default put temp files on the same small PVC as the database
- **Assumed DNS would be stable during long transfers** - DNS TTL expiry during a 10-minute upload is entirely predictable in hindsight

## What Helped

- **Traefik access logs with response times** - The exact 60000ms timing on the 504 immediately pointed to a timeout, and the PATCH vs PUT distinction showed which stage was failing
- **Traceroute from inside the pod** - Showed traffic going through VPN hops (10.64.0.1), immediately identifying the routing issue
- **ifconfig.me comparison** - Different exit IPs for desktop (VPN exempt) vs pod (VPN routed) confirmed the VPN theory
- **`du -sh` on the Longhorn mount** - Instantly found 9.7GB of stale temp files
- **OOMKilled in pod describe** - Clear signal, no ambiguity
- **Zot already deployed as a mirror** - Provided an immediate alternative registry that was purpose-built for the job

## What Could Have Been Worse

- **If the SQLite database had been corrupted** rather than just returning "disk full", data loss would have occurred
- **If there were no NFS available**, the disk pressure issue would have required a PVC resize and extended downtime
- **If this were a multi-user Forgejo instance**, the filled disk would have affected all users, not just CI
- **If the OOMKill had happened during a database write**, SQLite corruption was possible

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This exposed two systemic issues:

1. **Forgejo's built-in package registry is not suitable for large container images.** It buffers blobs in memory, stores temp files on the main volume, and has no streaming digest computation. This is not a configuration problem - it's an architectural limitation.

2. **Docker bridge networking inside dind is inherently problematic in k8s.** MTU mismatches, NAT overhead, DNS isolation, and LoadBalancer hairpins are all consequences of the extra network namespace. Host networking eliminates the entire category.

## Action Items

- [x] Switch runner job containers to `network: host`
- [x] Wire up Zot as the internal container registry (containerd trust, dind insecure-registries)
- [x] Move Forgejo `CHUNKED_UPLOAD_PATH` to NFS (defense in depth even if registry moves to Zot)
- [x] Deploy registries.yaml to all k3s nodes
- [ ] Update persona-mcp CI workflow to push to `zot.zot.svc.cluster.local:5000`
- [ ] Add PVC utilization alerts (Longhorn volume monitoring)
- [ ] Consider disabling Forgejo's package registry entirely if Zot handles all container images

## Lessons

- **When a fix reveals a new error, assume there are more.** Five stacked failures is unusual but not impossible when the path is deep enough
- **Host networking is the right default for dind-based CI runners in k8s.** Bridge networking adds a layer of complexity that creates MTU, DNS, and throughput problems
- **Use purpose-built tools.** Forgejo is a git forge, not a container registry. Zot is a container registry. The right tool for the job handles large blobs without OOMing
- **Check disk usage after failed operations that buffer large files.** Failed uploads leave temp files that accumulate silently
- **VPN policy routing makes network debugging deceptive.** Traffic that works from one host fails from another with no obvious reason unless you know about the routing rules
- **60 seconds is not a universal timeout.** Registry uploads, database migrations, and large file transfers all need explicit timeout configuration
