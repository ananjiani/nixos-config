---
date: 2026-01-25
title: MetalLB hairpin NAT prevents pods from reaching LoadBalancer IPs
severity: minor
duration: 30m
systems: [k3s, metallb, traefik, forgejo-runner]
tags: [kubernetes, networking, metallb]
commit: https://codeberg.org/ananjiani/infra/commit/3fb2ca7
---

## Summary

Forgejo runner pods couldn't reach Attic cache via the MetalLB LoadBalancer IP (192.168.1.52). The workflow failed when trying to pull/push to the Attic cache. Worked around by using theoden's direct LAN IP (192.168.1.27) instead.

## Timeline

All times CST.

- **~14:00** - Mkdocs workflow failing with "Couldn't resolve host name" for attic.dimensiondoor.xyz
- **~14:05** - Discovered attic.dimensiondoor.xyz only exists in local DNS, not public DNS
- **~14:10** - Switched to public URL (https://attic.dimensiondoor.xyz), still failed with NXDOMAIN
- **~14:15** - Realized the domain resolves to 192.168.1.52 (private IP) - only in local DNS
- **~14:20** - Tested pod connectivity: could reach codeberg.org but not 192.168.1.52
- **~14:25** - Discovered pod could ping boromir (192.168.1.21) but not 192.168.1.52
- **~14:30** - Identified 192.168.1.52 as MetalLB LoadBalancer IP for Traefik
- **~14:35** - Tested direct connectivity to theoden (192.168.1.27) - worked
- **~14:40** - Updated workflow to use theoden's direct IP, confirmed working

## What Happened

The Forgejo runner workflow needed to reach the Attic cache to pull dependencies and push build artifacts. Initially configured with `theoden.lan:8080`, which the runner pod couldn't resolve (CoreDNS doesn't know local DNS names).

Switched to the public hostname `attic.dimensiondoor.xyz`, but this only exists in local DNS and resolves to 192.168.1.52 - the MetalLB LoadBalancer IP for Traefik.

Testing revealed the pod could reach other LAN hosts (boromir at 192.168.1.21, theoden at 192.168.1.27) but not the MetalLB VIP at 192.168.1.52. Ping packets were sent but never received back - classic asymmetric routing symptom.

The issue is hairpin NAT: when a pod inside the cluster tries to reach a LoadBalancer IP served by the same cluster, the return path breaks. The packet reaches Traefik, Traefik connects to theoden, but the response routing fails because the source IP is a pod IP (10.42.x.x).

## Contributing Factors

- MetalLB LoadBalancer IPs are not designed for intra-cluster access
- Local DNS names (theoden.lan, attic.dimensiondoor.xyz) not available to CoreDNS
- Traefik configured with `externalTrafficPolicy: Local` which affects return routing
- No ClusterIP service for Attic (it's external to k8s)

## What I Was Wrong About

- **Assumed pods could reach any IP the node could reach** - LAN IPs yes, but not the cluster's own LoadBalancer IPs due to hairpin NAT
- **Assumed MetalLB VIPs work uniformly** - They work for external clients, but intra-cluster access has routing complications
- **Assumed the public DNS hostname would work** - It resolved to a private IP that had the same hairpin problem

## What Helped

- Pod could reach other LAN hosts, which isolated the problem to specifically 192.168.1.52
- `ping` with packet loss stats clearly showed asymmetric routing (packets sent, none received)
- Attic running on a separate host (theoden) with its own LAN IP provided an easy workaround

## What Could Have Been Worse

- If Attic were running inside k8s, there would be no direct IP workaround - would need to fix CoreDNS or use ClusterIP
- If this were a production service with no alternative path, would have caused extended outage

## Is This a Pattern?

- [x] Pattern: Revisit the approach

Any service accessed via MetalLB from inside the cluster will have this issue. This affects:
- CI runners accessing internal services via public URLs
- Any pod-to-LoadBalancer-IP traffic

Options to fix systematically:
1. Add local DNS entries to CoreDNS for internal services
2. Use ClusterIP services for intra-cluster access, LoadBalancer only for external
3. Configure split-horizon DNS (internal vs external resolution)

## Action Items

- [ ] Document which services are affected by hairpin NAT limitation
- [ ] Consider adding CoreDNS custom entries for internal service hostnames
- [ ] Evaluate whether Attic should run in k8s with a ClusterIP service

## Lessons

- **MetalLB LoadBalancer IPs are for external access only** - don't use them from inside the cluster
- **Test pod connectivity explicitly** - `kubectl exec ... -- ping <ip>` reveals routing issues
- **Asymmetric routing shows as "packets sent, none received"** - the telltale sign of hairpin/NAT issues
- **Direct IPs work when LoadBalancer IPs don't** - useful workaround for external services
