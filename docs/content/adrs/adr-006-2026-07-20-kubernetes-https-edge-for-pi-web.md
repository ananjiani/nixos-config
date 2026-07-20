---
date: 2026-07-20
title: Kubernetes HTTPS edge for pi-web on the desktop
status: accepted
supersedes:
superseded_by:
systems: [pi-web, ammars-pc, k3s, traefik, cert-manager, adguard, cloudflare]
tags: [pi, tls, ingress, networking]
---

## Context and Problem Statement

pi-web (ygncode/pi-web) is a browser UI for the Pi coding agent. It must run on ammars-pc: it attaches to local Pi sessions, spawns `pi` subprocesses, and needs the desktop's credentials, workspaces, and toolchains — none of which exist anywhere else. The binary itself only serves plain HTTP (bind address + `PI_WEB_TOKEN` bearer auth; non-loopback binds without a token require an explicit `-insecure` flag).

We want to reach it from other devices as `https://pi.dimensiondoor.xyz` with a real certificate, without standing up new TLS machinery on the desktop. The question is only where TLS termination lives — the workload placement is fixed by pi-web's local-state requirement.

## Decision Drivers

- pi-web must execute on ammars-pc; only the HTTPS front-end is negotiable
- Reuse existing, already-maintained infrastructure (k3s Traefik + cert-manager with `letsencrypt-prod` DNS-01, AdGuard split-DNS, Cloudflare-managed internal A records)
- No new ACME clients, reverse proxies, or auth layers to operate
- The `*.dimensiondoor.xyz` convention: internal services resolve to the Traefik LoadBalancer (`192.168.1.52`) and get per-host Certificates

## Considered Options

1. **Direct HTTP over the tailnet / Headscale** — no TLS edge, reach pi-web by tailnet IP or via `tailscale serve`
2. **Local Caddy on the desktop with DNS-01** — terminate TLS on ammars-pc itself
3. **Run pi-web inside k8s** — Deployment behind the existing Traefik ingress
4. **pi-web on the desktop + k8s HTTPS edge** — selectorless Service + manual EndpointSlice pointing Traefik at `192.168.1.50:31415`

## Decision Outcome

Chosen option: **pi-web on the desktop + k8s HTTPS edge**. The cluster already terminates TLS for a dozen internal hosts with cert-manager DNS-01 and Traefik; pointing a selectorless Service at the desktop reuses all of it (the exact pattern already used for Home Assistant at `192.168.1.25`). The incremental cost is four small manifests, one AdGuard rewrite, and one Cloudflare A record — no additional TLS/proxy daemon.

The backend hop Traefik → desktop is plain HTTP on the LAN, protected by pi-web's `PI_WEB_TOKEN` (generated once at Home Manager activation into `~/.config/pi-web/env`, mode 0600, never in the Nix store) and by binding only to `192.168.1.50` with the firewall opening port 31415 solely on `eno1`. The interface-scoped firewall limits which paths can reach the port but does not prevent interception by other hosts on the LAN segment; the trusted LAN is the accepted mitigation, matching the trust level already accepted for the Home Assistant backend hop.

### Consequences

- Good: real Let's Encrypt certificate and stable name with zero new TLS infrastructure; renewal, DNS, and ingress are all existing, monitored paths
- Good: desktop stays a pure HTTP service — no ACME keys or proxy config on ammars-pc
- Bad: ammars-pc becomes an availability dependency for `pi.dimensiondoor.xyz`; when the desktop sleeps or is off, the ingress returns 502/504 (acceptable — the service is meaningless without the desktop anyway)
- Bad: the manual EndpointSlice hardcodes `192.168.1.50`; if the desktop's LAN IP changes, the Service silently blackholes until the manifest is updated
- Neutral: token auth is pi-web's own; no Authentik/SSO layer in front (revisit if the host is ever exposed beyond LAN + tailnet)
- Bad: reduced feature scope — the declarative standalone-binary setup intentionally does not install the upstream Pi package extensions/skills, so `/web`, `/remote`, `/refresh`, the token commands, the pi-web ask-user tool, and the memory skill are unavailable in terminal Pi. Basic browser browsing/chat remains supported; returning to the terminal means reopening/resuming the session rather than `/refresh`

### Confirmation

- `kubectl kustomize k8s/apps/pi-web` renders; after Flux reconciles, the `pi-web-tls` secret exists and the Certificate is Ready
- `dig pi.dimensiondoor.xyz` returns `192.168.1.52` on LAN (AdGuard rewrite) and via public DNS (Cloudflare record)
- `curl -s http://192.168.1.50:31415` from another LAN host answers but denies session access without the token, and is refused from non-eno1 paths
- Browser to `https://pi.dimensiondoor.xyz` gets a valid LE cert and, with the token, a working pi session; `systemctl --user status pi-web` survives logout (linger)

## Pros and Cons of the Options

### Direct HTTP over the tailnet / Headscale

- Good: nothing new to deploy; tailnet ACLs already gate access
- Bad: our control plane is Headscale (ADR-002), which cannot provision the Tailscale-native HTTPS certificates that `tailscale serve` relies on — so this path yields plain HTTP with browser warnings, secure-context breakage, and a raw IP:port UX
- Bad: unreachable from LAN devices that aren't on the tailnet

### Local Caddy on the desktop with DNS-01

- Good: TLS terminates at the workload; no LAN-HTTP backend hop at all
- Bad: a second ACME stack to operate (Cloudflare API token on the desktop, renewal monitoring) duplicating what cert-manager already does for every other internal host
- Bad: breaks the repo convention that `*.dimensiondoor.xyz` internal hosts resolve to Traefik at `192.168.1.52`

### Run pi-web inside k8s

- Good: the "normal" pattern for this cluster; health-checked, no desktop dependency for the edge
- Bad: non-starter — pi-web's entire purpose is the desktop's local Pi sessions, credentials, workspaces, and subprocesses; a pod has none of them, and exporting them (SSH from pod to desktop, mounted homes) is strictly worse than proxying

### pi-web on the desktop + k8s HTTPS edge (chosen)

- Good: reuses Traefik, cert-manager, AdGuard, and Terraform DNS exactly as-is; proven selectorless-Service pattern (Home Assistant)
- Good: smallest possible desktop footprint — one user service, one firewall port on `eno1`
- Bad: desktop availability dependency and hardcoded EndpointSlice IP (above)
- Bad: token travels over unencrypted LAN HTTP between Traefik and the desktop; the interface-scoped firewall and LAN-only bind narrow exposure but do not prevent interception on the LAN segment — the trusted LAN itself is the accepted mitigation
