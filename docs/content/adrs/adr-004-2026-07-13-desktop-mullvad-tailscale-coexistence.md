---
date: 2026-07-13
title: Stop excluding Tailscale from Mullvad on ammars-pc (route tailnet through Mullvad)
status: proposed
supersedes:
superseded_by:
systems: [tailscale, mullvad, opnsense, headscale, erebor, openbao, vault-agent]
tags: [networking, vpn, desktop, split-tunnel]
---

## Context and Problem Statement

The desktop `ammars-pc` runs two overlay VPNs at once: Mullvad (privacy egress) and Tailscale (tailnet access to the homelab). To make them coexist, `tailscaled` is wrapped in `mullvad-exclude`, which places it in Mullvad's split-tunnel cgroup so tailnet traffic bypasses the Mullvad tunnel. Making that exclusion actually work has required a growing stack of custom `ip rule` entries, nftables mark/ct-mark rules, and DNS overrides — and it has now produced **four** postmortems in three months (2026-04-07 triple-fault, 2026-04-08 bypass-never-loaded, 2026-04-10 DNS DRY regression, 2026-07-11 type-route re-fib dead). Each fix resolved one interaction and exposed another. The 2026-07-11 incident showed the exclusion mechanism is fundamentally fragile on kernel 6.18: Mullvad adds its policy rules with no fixed priority, so its tunnel-catch rule perpetually leapfrogs any bypass rule we install, and nftables `type route` re-fib (the mechanism Mullvad's own split-tunnel depends on) is a silent no-op on this kernel.

Two facts reframe the original decision:

1. **The router already treats the desktop as VPN-exempt.** `terraform/opnsense.tf` puts `192.168.1.50` (ammars-pc) in `vpn_exempt_devices`, so OPNsense routes the desktop's direct egress out the bare ISP WAN, *not* through the router's Mullvad gateway. The desktop's local Mullvad daemon is therefore the *only* thing providing privacy egress — it is not redundant — and the Edge split-tunnel works because `mullvad-exclude`d Edge traffic hits the router as VPN-exempt and exits clearnet with the residential IP.

2. **The original reason for the exclusion is obsolete.** Tailscaled was excluded so it could reach the Headscale control plane. When Headscale lived in k3s (behind the internal VIP `192.168.1.52` via AdGuard split-DNS), routing tailscaled through Mullvad broke control-plane reachability: DNS resolved `ts.dimensiondoor.xyz` to the public WAN IP and the connection required a NAT hairpin that **OPNsense cannot do** (2026-04-07 postmortem). ADR-002 moved Headscale to erebor on 2026-04-20; `ts.dimensiondoor.xyz` now points at erebor's public IP `91.99.82.115` with no split-DNS rewrite and no hairpin. Reaching Headscale through Mullvad is now unproblematic.

## Decision Drivers

- Eliminate the recurring incident class — the exclusion machinery is the common root cause across four postmortems
- Single operator; silent, latent failures (Tailscale holds sessions across reboots) are expensive to diagnose
- Preserve the Edge split-tunnel (clearnet / residential IP for work) — this is a hard requirement
- Preserve Mullvad privacy egress for the desktop's general traffic
- Prefer deletion over adding more guardrails to a fragile stack
- Tailnet is used for management (SSH, `bao`, deploy-rs, vault MCP), not high-bandwidth transfers — latency tolerance is high

## Considered Options

1. **Stop excluding Tailscale; route tailnet through Mullvad.** Set `excludeFromMullvad = false` (tailscaled's own DERP/WG traffic rides the Mullvad tunnel), and replace the fragile bypass with a *minimal, drift-immune* remnant: a `100.64.0.0/10 dev tailscale0` route in the **main** table (resolved by Mullvad's own `suppress_prefixlength 0` rule, which always sits above its tunnel-catch) plus an nft **filter** ct-mark fixup so Mullvad's firewall accepts CGNAT packets leaving `tailscale0`. This is still required because Mullvad's tunnel-catch `ip rule` hijacks *any* unmarked process's traffic to tailnet IPs (e.g. `vault-agent` → `100.64.0.21:8200`) into the tunnel, where CGNAT is unroutable. What gets deleted is the tailscaled cgroup exclusion, the SO_MARK/mole `ip rule` stack, and all `type route` re-fib. Keep local Mullvad and the Edge exclude unchanged.
2. **Flip to router-side Mullvad for the desktop** — remove ammars-pc from `vpn_exempt_devices` so OPNsense Mullvads it, delete local Mullvad entirely, and reconstruct the Edge split-tunnel as a dedicated source IP that stays VPN-exempt at the router (via netns or source-based SNAT).
3. **Keep the current exclusion design, make the bypass drift-proof** — anchor CGNAT routing on a main-table route resolved by Mullvad's own `suppress_prefixlength 0` rule (immune to priority drift), and keep the ct-mark fixup.
4. **Status quo** — accept periodic breakage and fix by hand each time.

## Decision Outcome

Chosen option: **Option 1 — stop excluding Tailscale and route tailnet through Mullvad**, because the sole historical blocker (internal-Headscale NAT hairpin) disappeared with the ADR-002 erebor migration, it removes the fragile exclusion machinery rather than adding to it, and it leaves the Edge split-tunnel and Mullvad privacy egress untouched. The only cost is tailnet latency, which is acceptable for a management-only tailnet.

Note: this is a large simplification, not a total deletion. A small remnant survives — the main-table CGNAT route + ct-mark fixup — because reaching tailnet IPs from *unmarked* local processes requires escaping Mullvad's tunnel-catch `ip rule` regardless of whether tailscaled is excluded. The remnant is deliberately anchored on Mullvad's `suppress_prefixlength 0` rule so it is immune to the priority drift that caused the 2026-07-11 incident (Mullvad adds its rules with no fixed priority; a companion suppress rule that skips only default routes always precedes the tunnel-catch, so a `/10` route in main is resolved before the tunnel is consulted).

Adoption is **gated on a reboot-authentication test** (see Confirmation): tailscaled must re-authenticate to Headscale *through* Mullvad from a cold boot, not merely appear to work in a live session. Tailscale's session persistence hid the 2026-04-10 regression for ~40 hours, so a live-only test is not sufficient evidence.

### Consequences

- Good: Removes the root cause shared by four postmortems — no more `mullvad-exclude` cgroup, SO_MARK/mole bypass `ip rule`s, or `type route` re-fib dependence
- Good: Large net simplification in `hosts/desktop/configuration.nix` and one fewer moving part on every Mullvad reconnect/relay change
- Good: tailnet stays direct via `eno1` (Tailscale's own fwmark) — no latency or throughput cost; direct peer WG preserved (155 ms pong to erebor observed)
- Good: The remnant is nft filter hooks + one main-table route — drift-immune, no racing Mullvad's rule priorities
- Good: Edge split-tunnel and desktop Mullvad privacy egress are unchanged; `privacy.mullvadCustomDns` LAN-only invariant is untouched
- Neutral: tailscaled's underlay egresses the residential IP (as it did under the exclusion) — fine, peers are yours and DERP is Tailscale's
- Bad: Boot ordering matters — Mullvad's kill-switch RSTs tailscaled ("connection refused", NoState) whenever the ct-mark table is absent, so the table must exist before tailscaled authenticates; the CGNAT route also needs `tailscale0` up (handled by an `ExecStartPre` wait + `partOf = tailscaled`)

### Confirmation

Adopt only if all pass after a **full reboot**:

- `sudo systemctl restart tailscaled` is *not* the test — reboot so tailscaled does a fresh control-plane auth through Mullvad
- `tailscale status` shows `erebor` reachable (relay or direct) within ~30 s of boot
- `curl -sf --connect-timeout 4 http://100.64.0.21:8200/v1/sys/health` returns healthy JSON (OpenBao over tailnet, through Mullvad)
- `vault-agent-default.service` reaches `active` and `/run/secrets/{kimi_code_api_key,zai_api_key,opencode_api_key}` render
- Edge still egresses clearnet: its public IP is the residential ISP IP, not a Mullvad exit
- `mullvad status` still `Connected`; general (non-Edge) traffic still shows a Mullvad exit IP
- Stable across at least one additional reboot before deleting the bypass code permanently (guards against a latent session-persistence false-positive)

If any fail, fall back to Option 3 (drift-proof the existing exclusion) rather than reverting to the broken July-11 state.

## Pros and Cons of the Options

### Option 1 — Route tailnet through Mullvad (stop excluding)

- Good: Deletes the exclusion/bypass fragility (cgroup wrap, SO_MARK/mole rules, type-route re-fib); simplest coexistence given two VPNs
- Good: Newly unblocked — the erebor Headscale migration removed the NAT-hairpin dependency that forced exclusion
- Good: Edge split-tunnel and Mullvad privacy egress unaffected; no router changes
- Good: tailnet stays direct via `eno1` — no latency/throughput regression (the exclusion was firewall-acceptance, not routing)
- Neutral: Retains an nft ct-mark table + one main-table CGNAT route — not a total deletion, but drift-immune
- Bad: Mullvad's kill-switch RSTs tailscaled whenever the ct-mark table is absent, so the table must be present before tailscaled authenticates (boot ordering)

### Option 2 — Router-side Mullvad + per-IP Edge exemption

- Good: Architecturally cleanest end state — one overlay (Tailscale) on the desktop, zero VPN conflict, no local Mullvad
- Good: Moves the split decision from "per-app, fought by two VPNs" to "per-IP, one rule OPNsense already enforces" (`vpn_exempt_devices`)
- Good: Tailnet can run direct (no Mullvad in the path) — best tailnet performance
- Bad: Requires building per-IP Edge egress (network namespace with Wayland socket passthrough, or cgroup-mark → SNAT to a dedicated source IP) — its own non-trivial moving part
- Bad: Router change (remove ammars-pc from `vpn_exempt_devices`, add the Edge IP) plus desktop change — larger blast radius
- Bad: Desktop loses a local Mullvad kill-switch option entirely (currently off, but removes the possibility)

### Option 3 — Drift-proof the existing exclusion

- Good: Keeps direct tailnet performance; smallest behavioral change
- Good: The main-table-route anchor (rides Mullvad's own `suppress_prefixlength 0` rule) is genuinely immune to the priority drift that caused 2026-07-11
- Neutral: Still retains a ct-mark fixup for Mullvad's firewall accept
- Bad: Keeps the dual-VPN coupling and most of the machinery; four postmortems say this stack finds new ways to fail
- Bad: Still depends on Mullvad-internal behavior (suppress rule ordering, cgroup semantics) that can change on a Mullvad or kernel bump

### Option 4 — Status quo

- Good: Zero work now
- Bad: Recurring manual firefighting; silent latent failures that block `bao`/deploy/secret rendering until noticed
- Bad: No path off the fragility treadmill

## Related

- Supersedes the "eliminate the dual-VPN stack" action item deferred in the 2026-04-10 postmortem
- Depends on ADR-002 (Headscale on erebor) — the enabling change
- Postmortems: 2026-04-07, 2026-04-08, 2026-04-10, 2026-07-11 (Mullvad × Tailscale cluster)
- The 2026-07-11 main-table-route insight is the basis for the Option 3 fallback
