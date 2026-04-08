---
date: 2026-03-08
title: Missing IPv4 forwarding on rivendell breaks cross-node pod traffic
severity: moderate
duration: ~15m (detection to fix)
systems: [k3s, flannel, rivendell, traefik]
tags: [kubernetes, networking, sysctl, flannel, nixos]
commit: https://codeberg.org/ananjiani/infra/commit/6dac098
---

## Summary

All services with backend pods on rivendell (Forgejo, Bifrost, Headscale, Open-WebUI) were returning 504 gateway timeouts via Traefik. The cause was `net.ipv4.ip_forward = 0` on rivendell, which prevented the kernel from forwarding packets from the host network into the cni0 bridge for pod delivery. Other nodes were unaffected because their Tailscale module happened to enable IPv4 forwarding as a side effect.

## Timeline

All times CST.

- **~10:15** - During routine cluster health check (after deploying Zot nodeSelector change), noticed Forgejo and Bifrost inaccessible via browser.
- **~10:17** - Verified all pods Running and Ready. Traefik logs showed 504s (30s timeout) on all backends with 10.42.0.x IPs (rivendell's pod CIDR). Backends on other nodes (homepage, home-assistant) returned 200 in <10ms.
- **~10:19** - Confirmed flannel route on samwise was correct (`10.42.0.0/24 via 192.168.1.29`). Host-to-host ping from samwise to rivendell worked. Direct pod-to-pod wget from Traefik pod to Forgejo pod timed out.
- **~10:21** - Checked `sysctl net.ipv4.ip_forward` on rivendell: `0`. All other nodes: `1`.
- **~10:22** - Applied `sysctl -w net.ipv4.ip_forward=1` on rivendell. Cross-node pod traffic immediately restored. Forgejo returned 200.
- **~10:25** - Restarted Authentik PostgreSQL (stale postmaster.pid from the period without forwarding). Deleted Forgejo pod to reset CrashLoopBackOff on its init container (OIDC discovery to Authentik was returning 503 during Authentik's restart).
- **~10:30** - All pods healthy. Added `net.ipv4.ip_forward = 1` to the k3s module as a permanent fix.

## What Happened

While investigating Zot's NFS scheduling and performing a cluster health check, we discovered that Forgejo and Bifrost were inaccessible. Traefik was running fine on samwise and could reach backends on boromir and theoden, but every request to pods on rivendell timed out after 30 seconds.

The flannel host-gw routes looked correct and host-level ping worked, which pointed away from a routing problem and toward something on rivendell itself. Checking `ip_forward` revealed it was disabled. With forwarding off, packets arriving on rivendell's `ens18` interface destined for the 10.42.0.0/24 pod CIDR were silently dropped instead of being forwarded to the `cni0` bridge.

The fix was a single sysctl. The question was why rivendell was the only node affected: the k3s module had always set `net.ipv6.conf.all.forwarding = 1` but never `net.ipv4.ip_forward`. The other three nodes got IPv4 forwarding from the Tailscale module, which sets it when `exitNode` or `subnetRoutes` is enabled. Rivendell has Tailscale disabled entirely due to an unrelated r8169 NIC driver bug, so nothing on the system enabled IPv4 forwarding.

## Contributing Factors

- **k3s module omitted `net.ipv4.ip_forward`**: It set IPv6 forwarding but not IPv4, relying on an implicit assumption that something else would handle it.
- **Tailscale module as accidental provider of ip_forward**: On the three server nodes, Tailscale's sysctl for exit node routing was the only thing enabling IPv4 forwarding. This was a coincidence, not a deliberate design decision.
- **Rivendell's Tailscale disabled for unrelated hardware reasons**: The Realtek r8169 NIC driver has a bug where Tailscale's netfilter modifications cause complete inbound packet loss after ~11 minutes. Disabling Tailscale removed the accidental ip_forward side effect.
- **No monitoring for sysctl state**: Nothing alerts when a critical sysctl like ip_forward is off on a k3s node.

## What I Was Wrong About

- **"k3s handles ip_forward itself"**: I assumed k3s or flannel would enable IPv4 forwarding as part of their startup. k3s does set some sysctls at runtime, but `ip_forward` wasn't reliably among them on NixOS where systemd-sysctl runs after k3s starts, potentially resetting values.
- **"All k3s nodes have the same effective sysctl config"**: The mental model was that the k3s module defines the networking baseline for all nodes. In reality, the Tailscale module was silently papering over a gap in the k3s module, but only on nodes where Tailscale was active.

## What Helped

- **Traefik access logs with backend IPs**: Made it immediately obvious that all failing backends shared the 10.42.0.x CIDR (rivendell), while other nodes worked fine.
- **Quick sysctl check**: The pattern of "host ping works, pod traffic doesn't, only one node affected" pointed directly at a forwarding issue. One `sysctl` command confirmed it.
- **Previous flannel debugging experience**: Having recently debugged flannel route corruption (2026-03-02), the diagnostic path of checking routes, then forwarding, then iptables was already familiar.

## What Could Have Been Worse

- **If Traefik had been scheduled on rivendell**: Traefik itself would have been unreachable from MetalLB, taking down all ingress, not just backends on one node.
- **If this had happened during the flannel VIP corruption incident**: Would have been extremely difficult to distinguish from the routing issues, potentially leading to hours of misdirected investigation.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This is the second time a critical networking sysctl was missing from the k3s module (the first being the IPVS firewall rule). The pattern is: **the k3s module doesn't fully declare its networking prerequisites, relying on other modules or runtime behavior to fill gaps.** Each gap only manifests when a specific node diverges from the "typical" configuration.

## Action Items

- [x] Add `net.ipv4.ip_forward = 1` to k3s module sysctl (commit 6dac098)
- [ ] Deploy updated NixOS config to rivendell to make the fix persistent across reboots
- [ ] Audit k3s module for other sysctls that k3s/flannel expects but doesn't declare (e.g., `bridge-nf-call-iptables`)
- [ ] Consider adding a simple systemd health check that verifies critical sysctls after boot

## Lessons

- **Declare all prerequisites explicitly in the module that needs them.** Don't rely on other modules coincidentally providing sysctls, kernel modules, or packages. If k3s needs `ip_forward`, the k3s module should set it — even if Tailscale also sets it on most nodes.
- **When one node behaves differently, check what modules are disabled on it.** Rivendell's unique config (no Tailscale) made it the canary for implicit dependencies.
- **504s where host ping works but pod traffic doesn't = check ip_forward.** This is the first thing to verify when cross-node pod connectivity fails with correct routes.
