---
date: 2026-07-20
title: pi-web gateway timeout after reboot — stale NixOS system profile
severity: moderate
duration: ~1h 1m (pi-web remotely unavailable ~50m; remediation degraded Tailscale/OpenBao until 21:46)
systems:
  [
    pi-web,
    ammars-pc,
    nixos,
    home-manager,
    firewall,
    k3s-traefik,
    cert-manager,
    headscale,
    tailscale,
    mullvad,
    openbao,
    vault-agent,
  ]
tags: [nixos, networking, kubernetes, firewall, tailscale, mullvad]
commit: https://codeberg.org/ananjiani/infra/commit/df8a8cdd
related:
  - 2026-07-11-1521-mullvad-type-route-refib-dead.md
---

## Summary

After a reboot of ammars-pc, the newly deployed pi-web HTTPS edge
(`pi.dimensiondoor.xyz` → k3s Traefik → desktop backend `192.168.1.50:31415`,
per ADR-006) returned gateway timeouts for ~50 minutes. The desktop had been
switched to the new firewall config via a direct `switch-to-configuration
switch` on the built closure — which updated the live system but **not**
`/nix/var/nix/profiles/system` — so the reboot came back on the old profile
without the eno1 TCP 31415 allow rule. Corrective switching then exposed a
second, latent regression: only one of the two required Mullvad bypass marks
was configured, blackholing Tailscale/OpenBao and failing vault-agent until
21:46.

## Timeline

All times CDT, 2026-07-20.

- **Earlier evening** - pi-web k8s HTTPS edge built out per
  `docs/content/adrs/adr-006-2026-07-20-kubernetes-https-edge-for-pi-web.md`
  (commits `8c81fefe`, `d187d858`, `3d68e2db`). Verification passed: pi-web
  active on `192.168.1.50:31415`, Traefik EndpointSlice populated, Let's
  Encrypt cert Ready, unauthenticated HTTPS 401, authenticated HTTPS 200.
- **Earlier evening** - `nh os switch` could not sudo without a TTY. A
  privileged workaround ran the built closure's `switch-to-configuration
  switch` directly. Live system now had the firewall rule; the system profile
  silently did not.
- **20:45** - ammars-pc rebooted. It came up on the old profile
  (`s1f4162...`), which has no firewall allow for eno1 TCP 31415.
- **20:46** - pi-web service started and answered 401 locally, but curls from
  Boromir and Traefik timed out; browser showed gateway timeout.
- **~21:32** - Investigation compared the three hops: local curl 401,
  EndpointSlice correct, cert Ready, Boromir/Traefik timeout. Both
  `/run/current-system` and `/nix/var/nix/profiles/system` pointed at the
  stale profile, while the freshly evaluated desired closure contained
  `[31415]` in the firewall rules.
- **~21:35** - Set `/nix/var/nix/profiles/system` to the desired closure with
  `nix-env --set`, then ran its `switch-to-configuration switch`. Firewall
  reloaded; Boromir and Traefik got 401; authenticated public HTTPS returned
  200. pi-web restored.
- **~21:35–21:45** - The corrective switch surfaced a second issue: Tailscale
  in NoState while Mullvad was connected, OpenBao at `100.64.0.21` timing
  out, vault-agent repeatedly failing waiting for secrets. Config had
  regressed to only `ct mark 0x00000f41` — the required `meta mark
  0x6d6f6c65` was missing. Committed the restore of both marks (`df8a8cdd`).
- **21:46** - After one Mullvad disconnect/reconnect, Tailscale established
  its control session; erebor/OpenBao reachable through Mullvad; vault-agent
  active. Confirmed resolved.

## What Happened

The evening's project was moving pi-web's public HTTPS edge into the k3s
cluster (ADR-006): Traefik on the cluster terminates TLS for
`pi.dimensiondoor.xyz` and proxies to pi-web running on the desktop over the
LAN. A tailnet backend was also tested but ruled out because Traefik currently
runs on rivendell, where Tailscale is permanently disabled; the LAN backend
was chosen. The desktop config gained a firewall allow for eno1 TCP 31415.

Applying that config hit a snag: `nh os switch` couldn't sudo without a TTY in
the session being used. The workaround was to build the closure and run its
`switch-to-configuration switch` directly with privileges. This worked — all
end-to-end checks passed (local 401, EndpointSlice, cert Ready, unauth 401,
authed 200) — and the assumption was that the system was fully deployed.

It wasn't. `switch-to-configuration switch` activates the configuration
(`/run/current-system`) but does not advance `/nix/var/nix/profiles/system`.
It does invoke the bootloader installer, but systemd-boot enumerates NixOS
generations from that profile; because the desired closure was absent there,
it could not become the default boot generation. When the machine rebooted at
20:45, it booted the old profile. pi-web itself is managed at the user level and came up fine at 20:46,
answering 401 locally — but the firewall no longer allowed 31415 from the LAN,
so Boromir and Traefik timed out and the browser showed a gateway timeout.

Investigation at ~21:32 walked the path hop by hop: local backend healthy,
Kubernetes side (EndpointSlice, cert, Traefik config) all correct, only the
LAN hop dead. Comparing `/run/current-system` against the evaluated desired
closure exposed the stale profile. The correct remediation was `nix-env
--profile /nix/var/nix/profiles/system --set <closure>` **before**
`switch-to-configuration switch`, which reloaded the firewall and restored
pi-web end to end.

The remediation switching then surfaced a second problem: Tailscale sat in
NoState while Mullvad was connected, OpenBao timed out, and vault-agent looped
on failed secret fetches. The config had regressed from the documented
operational invariant that the Mullvad bypass needs **both** `ct mark
0x00000f41` and `meta mark 0x6d6f6c65` — only the ct marks remained. Commit
`df8a8cdd` restores both. Even with the marks fixed, Tailscale needed one
Mullvad disconnect/reconnect to establish its control session; once it did,
OpenBao worked through Mullvad and vault-agent went active at 21:46. The
cold-start behavior is not fully solved and is tracked as a follow-up.

A note on red herrings: the Flux `apps` Kustomization was already health-stuck
on unrelated persona-mcp, but the pi-web resources had applied — not causal.
AdGuard, DNS, the cert, and pi-web auth all worked throughout.

## Contributing Factors

- **`switch-to-configuration switch` does not update the system profile.**
  Run directly, it changes the live system only. Although it invokes the
  bootloader installer, systemd-boot derives generations from
  `/nix/var/nix/profiles/system`, which remains on the old generation.
  `nixos-rebuild`/`nh` do the `nix-env --set` step first.
- **TTY-less sudo forced an ad-hoc deployment path.** The tooling failure
  (`nh os switch` unable to sudo) pushed activation off the paved path onto a
  manual command whose semantics were only partially understood.
- **Verification was live-state only.** Every check after the workaround
  tested the running system; nothing tested "will this survive a reboot."
- **Latent bypass-mark regression.** The desktop config had drifted to only
  one of the two required Mullvad bypass marks (a documented invariant from
  the April/July incidents). The stale-profile remediation was the trigger
  that exposed it, compounding the outage with a Tailscale/OpenBao/vault-agent
  degradation.
- **Tailscale cold-start under Mullvad is fragile.** Even with correct marks,
  the control session did not establish until Mullvad was cycled once.
- **No external monitoring of `pi.dimensiondoor.xyz`.** The outage was
  noticed by using the service, not by any check.

## What I Was Wrong About

- **"Running the closure's `switch-to-configuration switch` is equivalent to
  `nh os switch`."** It is not: it updates `/run/current-system` but leaves
  `/nix/var/nix/profiles/system` (and therefore the next boot) on the old
  generation. The cold-boot workaround in the deploy-rs invariants uses
  `nix-env --set` first for exactly this reason.
- **"Verification passing means deployed."** All the end-to-end checks passed
  against ephemeral live state. The deployment was one reboot away from
  reverting and nothing measured that.
- **"The Mullvad bypass invariant was still intact."** Both marks are
  documented as required, but only the ct mark survived in the config; the
  regression sat latent until a switch churned networking state.

## What Helped

- **Hop-by-hop comparison** (local curl vs EndpointSlice vs cert vs
  Boromir/Traefik) isolated the failure to the desktop LAN hop quickly and
  cleared the Kubernetes side in minutes.
- **Prior postmortems and the operational invariants** named both required
  bypass marks and the `nix-env --set` cold-boot pattern — the second issue
  was recognized as a known class instead of a fresh mystery.
- **pi-web answering 401 locally** immediately ruled out the application and
  Home Manager layer, pointing at the network path.
- **The desired closure was still buildable and inspectable**, so "config
  says `[31415]`, runtime doesn't have it" was provable rather than guessed.

## What Could Have Been Worse

- **The stale profile could have reverted more than the firewall.** Any other
  system-level change in that generation gap (secrets wiring, services,
  networking) would have silently rolled back on the same reboot.
- **If the desktop had been remote-only**, the vault-agent/Tailscale
  degradation during remediation could have cut off the management path while
  mid-fix.
- **The bypass-mark regression could have surfaced during an unrelated,
  unattended reboot**, leaving OpenBao-dependent tooling broken with no one
  actively debugging.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Two patterns, both repeats:

1. **Live state diverging from declared/persistent state.** This is the same
   class as the April 8 "bypass table never loaded" incident: the system
   accepts a partial deployment without complaint, and verification only
   probes the live state. Any manual activation path that skips profile
   management recreates it.
2. **Mullvad×Tailscale on the desktop, again.** This is the fifth incident
   touching that stack. The both-marks invariant regressed despite being
   documented, and cold-start still requires a manual Mullvad cycle. The
   invariant needs a runtime check, not just documentation.

## Action Items

- [x] Set `/nix/var/nix/profiles/system` to the desired closure with
      `nix-env --set` and re-switch — pi-web restored end to end
- [x] Restore both Mullvad bypass marks (`ct mark 0x00000f41` **and**
      `meta mark 0x6d6f6c65`) —
      [df8a8cdd](https://codeberg.org/ananjiani/infra/commit/df8a8cdd)
- [ ] Prohibit (or wrap in a guard script) running `switch-to-configuration
      switch` without first setting the system profile; document the
      `nix-env --set` + switch pair as the only sanctioned manual path
- [ ] Add a post-activation assertion/check that `/run/current-system` and
      `/nix/var/nix/profiles/system` resolve to the same closure, flagging
      divergence loudly
- [ ] Add an external blackbox check (uptime probe or smoke script) for
      `https://pi.dimensiondoor.xyz` so remote unavailability is detected
      without manual use
- [ ] Investigate and fix Tailscale cold-start under Mullvad so a connected
      Mullvad session does not require a disconnect/reconnect for Tailscale
      to establish control — currently a recurring manual step, not solved
- [ ] Add a runtime check that both nft bypass marks are present in the
      loaded ruleset (extends the existing April 8 action item)

## Lessons

- **`switch-to-configuration switch` alone is a live-only activation.**
  Reboot persistence requires the system profile to be set first
  (`nix-env --profile /nix/var/nix/profiles/system --set <closure>`).
  If forced off `nh`/`nixos-rebuild`, do both steps or expect a revert.
- **Verify what survives a reboot, not just what runs now.** After any
  non-standard activation, compare `/run/current-system` with
  `/nix/var/nix/profiles/system` before calling it done.
- **"Local works, remote times out" on a freshly opened port means check the
  firewall's actual runtime state**, not the config that was supposed to be
  applied.
- **Documented invariants regress silently.** The both-marks requirement was
  written down and still drifted; invariants that matter need runtime
  enforcement or checks.
- **Remediation churn exposes latent failures.** Budget for a second problem
  when correcting the first, especially on the desktop's dual-VPN stack.
