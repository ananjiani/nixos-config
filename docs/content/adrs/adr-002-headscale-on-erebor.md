---
date: 2026-04-20
title: Move Headscale from k3s to erebor VPS
status: proposed
supersedes:
superseded_by:
systems: [tailscale, headscale, k3s, erebor, vault-agent, openbao]
tags: [infrastructure, networking, bootstrap, vps]
---

## Context and Problem Statement

Headscale (self-hosted Tailscale coordination server) currently runs as a k3s workload behind the Traefik VIP at `ts.dimensiondoor.xyz` (192.168.1.52). This creates a cold-boot deadlock: k3s on boromir/samwise/theoden blocks waiting for `/run/secrets/k3s_token` → vault-agent can't render the token because it can't reach OpenBao at `100.64.0.21:8200` → the Tailscale IP requires tailscaled to be authenticated → tailscaled is logged out and needs Headscale to re-auth → Headscale is in k3s. Today (2026-04-20), a planned physical move of three Proxmox hosts required manually SOPS-decrypting `k3s_token` and writing it to each server's `/run/secrets/` to break the cycle. Any future full-cluster outage (power cut, chassis move, rack work) will require the same manual intervention. ADR-001 already moved OpenBao to erebor for the same bootstrap reason — this ADR completes that pattern for the second in-cluster bootstrap dependency.

Execution tracked in [issue #85](https://codeberg.org/ananjiani/infra/issues/85) (migration steps, data migration, DNS cutover, k8s cleanup).

## Decision Drivers

- Cold-boot must be possible without manual secret intervention (recovery-time objective)
- Must preserve Tailscale operation during partial outages (warm cluster, VPS reachable, etc.)
- Single-operator constraint — operational complexity of recovery is a real cost
- Consistency with ADR-001: infrastructure the cluster depends on to start should not live in the cluster
- erebor already hosts the other bootstrap dependency (OpenBao), so no *new* critical host is introduced

## Considered Options

1. Move Headscale to erebor VPS alongside OpenBao
2. Keep Headscale in k3s, add SOPS fallback for `k3s_token` on servers
3. Switch to managed Tailscale (tailscale.com control plane)
4. Status quo — accept manual token-priming during cold boots

## Decision Outcome

Chosen option: "Move Headscale to erebor", because it eliminates the cold-boot deadlock by removing the dependency on k3s for tailnet authentication, mirrors the established OpenBao pattern, and does not introduce a new critical host (erebor is already in the bootstrap path).

### Consequences

- Good: Cold-boot works end-to-end without manual intervention — erebor provides both OpenBao and Headscale before the cluster starts
- Good: k3s outages no longer break new tailscale auth or node re-auth
- Good: erebor becomes the single, well-defined bootstrap dependency — easier to reason about and harden (backups, monitoring, DNS)
- Good: Removes one k8s HelmRelease, one IngressRoute, one MetalLB VIP dependency from the critical path
- Bad: erebor's blast radius grows — a VPS outage now affects both secrets delivery and new tailnet auth (mitigated: existing tailscale peers keep working via DERP for session lifetime of keys)
- Bad: Migration effort — stand up Headscale on erebor, re-register all nodes with new control URL, update ACLs, migrate any existing auth keys
- Bad: `ts.dimensiondoor.xyz` DNS and TLS move off cert-manager/Traefik; erebor needs its own ACME/Let's Encrypt path (or reuse existing erebor TLS terminator)
- Neutral: Headscale's admin UI (if any) moves from in-cluster to VPS — access pattern changes but not meaningfully

### Confirmation

This decision is working when: (1) a full cluster cold-boot (all k3s servers + Proxmox hosts off, then all on) results in all nodes joining tailnet and k3s forming quorum without manual SOPS decryption, (2) `tailscale status` on all nodes shows authenticated peering within 5 minutes of boot, (3) vault-agent-default on all servers reaches OpenBao and renders `/run/secrets/k3s_token` on first attempt. Test by doing a planned full shutdown + startup via `lab-shutdown --all && lab-startup --all`.

## Pros and Cons of the Options

### Move Headscale to erebor VPS

- Good: Eliminates cold-boot deadlock for the whole cluster
- Good: Consistent architecture with OpenBao (ADR-001) — one host handles all bootstrap dependencies
- Good: erebor's historical uptime exceeds k3s's — bootstrap availability improves
- Good: Simplifies the failure model: "is erebor up?" is a single check instead of a chain of k3s dependencies
- Good: No new recurring cost — erebor already provisioned and paid for
- Neutral: DERP means existing peers survive Headscale-on-erebor outages; only *new auth* breaks during VPS downtime
- Bad: Concentrates two critical services on one VPS — a single erebor compromise or failure affects both
- Bad: Headscale NixOS module (`services.headscale`) needs TLS config, DB persistence, backup strategy on erebor
- Bad: Migration involves brief tailnet disruption while nodes re-register with new control URL

### Keep Headscale in k3s, add SOPS fallback for `k3s_token` on servers

- Good: Minimal changes — just add `sops.secrets.k3s_token` alongside vault-agent and a `tokenFile` preference for whichever exists first
- Good: Preserves Headscale HA inside k3s (if configured that way)
- Good: No erebor blast radius growth
- Neutral: Matches what rivendell already does (SOPS for `k3s_token`)
- Bad: Doesn't actually solve the chicken-and-egg — tailscale still needs Headscale to re-auth after shutdown, and a SOPS fallback only fixes the k3s_token leg. vault-agent still can't reach OpenBao without tailscale during the window between boot and Headscale coming up.
- Bad: Makes the token-source logic dual: SOPS for cold boot, vault-agent for steady state. Divergence risk (rotation on one not the other).
- Bad: Leaves the architectural smell of critical infra inside the cluster it depends on

### Switch to managed Tailscale (tailscale.com)

- Good: Zero operational overhead — Tailscale operates the control plane
- Good: Highest availability of any option (Tailscale's SLA and scale)
- Good: No cold-boot concerns at all — control plane is always up
- Neutral: Free tier covers homelab scale (100 devices, 3 users)
- Bad: Reintroduces cloud vendor dependency that self-hosting Headscale was meant to eliminate
- Bad: Loses control over auth keys, ACLs, and audit data — they live on Tailscale's infrastructure
- Bad: Conflicts with the "fully self-hostable" principle driving ADR-001 and the broader homelab
- Bad: Undoes prior migration work to Headscale

### Status quo (manual token-priming during cold boots)

- Good: Zero migration effort
- Good: No change to blast radius or architecture
- Neutral: Cold boots are rare (handful per year)
- Bad: Every cold boot requires the operator to remember the manual procedure (SOPS decrypt → pipe to /run/secrets on each server) — high cognitive load at exactly the moment when things are already stressful
- Bad: The procedure requires the operator's workstation to be up and have the SOPS age key — a simultaneous workstation failure compounds the outage
- Bad: Undocumented recovery paths are the postmortem-generating kind — this ADR itself was triggered by today's near-miss
