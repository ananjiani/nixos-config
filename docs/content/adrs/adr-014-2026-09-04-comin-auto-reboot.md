---
date: 2026-09-04
title: Unattended Comin auto-reboot with staggered per-host windows
status: accepted
supersedes:
superseded_by:
systems: [comin, aragorn, boromir, samwise, theoden, erebor, denethor]
tags: [deployment, reboot, systemd, monitoring]
---

## Context and Problem Statement

Comin converges seven always-on servers from `main` but never reboots them. When a switch needs a reboot (kernel, module, initrd), the exporter metric `comin_need_to_reboot` sits at `1` until a human acts. That leaves the fleet half-applied and keeps the `CominNeedsReboot` alert noisy. The goal is unattended daily reboots that fire only when needed and stay non-disruptive for k3s quorum, Buildbot, and interactive sessions.

## Decision Drivers

- Hands-off: reboot without waiting for a human when Comin says reboot is needed
- Never drop k3s quorum (boromir / samwise / theoden are all `role = "server"`)
- Finish Aragorn before `ammars-pc-deploy.timer` at 04:30
- Skip surprise reboots after sleep/wake or boot loops
- Do not invent new drain logic where `k3s-graceful-drain` already exists
- Exclude rivendell (broken r8169 NIC path; k3s agent with no drain unit)

## Considered Options

1. **Comin built-in auto-reboot** — none exists; Comin only exposes the metric
2. **Activity-aware staggered per-host systemd timers** (chosen)
3. **Manual reboots driven by the `CominNeedsReboot` alert**

## Decision Outcome

Chosen option: **activity-aware staggered per-host systemd timers**, because Comin will not reboot itself and alert-driven manual reboots are not hands-off. Each enabled host gets `modules.comin.autoReboot` → `comin-auto-reboot.timer` (`Persistent=false`) calling a oneshot that:

1. Reads local `comin_need_to_reboot` from the Comin exporter (honor `listenAddress`; fall back to `127.0.0.1` only when the bind is all-interfaces)
2. Skips when uptime ≤ `minUptimeSec` (default 3600)
3. Skips when `loginctl list-sessions` shows any session (protects aragorn / denethor)
4. Runs optional `preRebootCheck` (theoden skips when `buildbot_builders_running_total` ≠ 0 on `127.0.0.1:9101`, or when that scrape fails)
5. Otherwise `systemctl reboot`

Stagger (local time):

| Host | OnCalendar |
| --- | --- |
| aragorn | 04:00 |
| boromir | 04:15 |
| samwise | 04:30 |
| theoden | 04:45 |
| erebor | 05:00 |
| denethor | 05:15 |

rivendell is not enabled. k3s servers already drain on shutdown and uncordon on boot via existing units, so plain `systemctl reboot` is enough.

### Consequences

- Good: Kernel/module switches converge without a human reboot step.
- Good: 15-minute stagger keeps at most one of three k3s servers rebooting at a time.
- Good: `Persistent=false` avoids surprise catch-up reboots after a host was off or asleep.
- Good: Session and Buildbot guards keep interactive and CI work safe.
- Bad: A host that is always logged in (or theoden always busy at 04:45) may stay at `comin_need_to_reboot=1` until the next clear window; the alert still covers that.
- Bad: Erebor takes a short public blip (Headscale control plane, ntfy, Caddy) on each needed reboot; OpenBao relies on AWS KMS auto-unseal.
- Neutral: `CominNeedsReboot` remains useful as a stuck-reboot signal, not the primary operator path.

### Confirmation

- Enabled hosts expose `comin-auto-reboot.timer` with the stagger table above; rivendell does not.
- With `comin_need_to_reboot=0`, the oneshot exits 0 and does not reboot (journal says skip).
- With metric `1`, no users, uptime ok, and precheck ok, the oneshot calls `systemctl reboot`.
- theoden skips while `buildbot_builders_running_total > 0` or metrics are unreachable.

## Pros and Cons of the Options

### Comin built-in auto-reboot

- Good: One knob owned by the deploy agent.
- Bad: Does not exist; would need upstream work and still need fleet-wide stagger policy.

### Activity-aware staggered per-host systemd timers (chosen)

- Good: Local, boring systemd; reuses the existing exporter metric and k3s drain units.
- Good: Per-host calendar and optional precheck encode fleet constraints in Nix.
- Bad: Policy lives in host config, not in Comin itself.

### Manual reboots via `CominNeedsReboot`

- Good: Maximum human judgment per reboot.
- Bad: Not hands-off; the metric already sits at 1 until someone acts — that is the problem.
