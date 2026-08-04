---
date: 2026-08-03
title: Denethor web search via LAN pinhole to SearXNG
status: accepted
supersedes:
superseded_by:
systems: [denethor, searxng, opnsense, pi]
tags: [denethor, isolation, search, networking, work-vpn]
---

## Context and Problem Statement

Denethor's coding agents had no web search: `piCodingAgent.searxngUrl = null` was part of the VM's blanket homelab isolation. After SearXNG gained a reliable API-backed engine (braveapi), Denethor was the only host without working agent search. Revisiting the isolation revealed its actual load-bearing constraint was never a personal threat model — it is that the employer's side can observe whatever passes through the corporate AnyConnect tunnel, and the work VPN pushes a full-tunnel default route (`default dev tun0`). Any access path for Denethor must therefore be invisible from inside that tunnel and must not add VPN-like network artifacts to the box.

## Decision Drivers

- Employer observability: nothing homelab-bound may enter tun0 or corporate DNS, and no mesh/VPN interface may appear alongside the work VPN
- The employer has no on-box agent (own openconnect client), so purely local traffic is unobservable
- Reuse the existing SearXNG stack (braveapi + scrapers, one Brave quota) rather than a second search account
- Keep Denethor's isolation auditable: explicit, narrow exceptions over broad connectivity
- Minimize new moving parts (keys, services, public endpoints)

## Considered Options

1. **Join Denethor to the Headscale mesh with a restrictive ACL**
2. **Expose SearXNG publicly via erebor (Caddy + token auth)**
3. **Direct Brave/Tavily API keys on Denethor, no homelab connectivity**
4. **LAN pinhole: OPNsense pass rule + pinned /32 route to the SearXNG ingress VIP** (chosen)

## Decision Outcome

Chosen option: LAN pinhole. One OPNsense rule (Denethor → 192.168.1.52 tcp/443, sequence 305, ahead of the work-VLAN private-networks block) plus three lines on Denethor: a pinned `192.168.1.52/32` route via the VLAN gateway (same pattern as the existing admin-host routes, keeps the traffic out of the full-tunnel default), a static `networking.hosts` entry (no `.lan` lookups against Quad9/corporate DNS), and the module-default `searxngUrl`. Traffic never leaves the local network and is invisible to the tunnel; verified working with the work VPN up.

### Consequences

- Good: Denethor gets the full multi-engine search stack with zero new accounts, keys, or services.
- Good: The exception is enumerable — one firewall rule, one /32, one hosts entry — and code review shows exactly what the work VM can reach.
- Bad: First hole in the work→LAN wall; a compromised Denethor can now reach one HTTPS service in the k3s cluster.
- Bad: Denethor search depends on homelab availability (k3s, SearXNG) where a direct API key would not.
- Neutral: If the work VPN client ever gains posture reporting (employer-managed client), on-box routes/flows become visible and this decision should be revisited toward option 3.

### Confirmation

`ip route get 192.168.1.52` on Denethor resolves via `ens18` (not `tun0`) while the work VPN is up, and `web-search <query>` returns results. The temporary-route test confirmed OPNsense blocks the path without the rule and passes it with the rule.

## Pros and Cons of the Options

### Headscale mesh + ACL

- Good: Encrypted, centrally managed allowlist; would also enable scoped OpenBao access later.
- Bad: Creates a `tailscale0` interface and WireGuard flows on a box running the corporate VPN — under full-tunnel, Tailscale's control/DERP traffic egresses through the corporate concentrator as unknown VPN traffic. Exactly what gets flagged; rejected on the deciding driver.

### Public HTTPS endpoint via erebor

- Good: Observationally identical to any SaaS API call; works under full-tunnel; pattern precedent exists (Headscale on erebor).
- Neutral: Personal domain appears in SNI/DNS — acceptable per operator.
- Bad: Requires exposing SearXNG (auth token, Caddy route, abuse surface, one more key file) for a problem the LAN already solves; queries transit the internet twice.

### Direct Brave/Tavily keys on Denethor

- Good: Zero homelab coupling in any direction; plain HTTPS to public APIs; survives homelab outages.
- Bad: Second Brave account/key to manage manually (no vault-agent on Denethor); loses multi-engine corroboration; splits quota management. The fallback if the pinhole must close.

### LAN pinhole (chosen)

- Good: Simplest; invisible to the employer vantage point; full search stack reused.
- Bad: Weakens work→LAN isolation by one service; requires the pinned-route discipline to keep traffic off tun0 (route regression would silently send searxng traffic into the corporate tunnel — the hosts entry and /32 are both declarative, mitigating this).
