---
date: 2026-08-19
title: Comin pull deployments with Buildbot CI and activity-aware desktop deploy
status: accepted
supersedes:
superseded_by:
systems: [comin, buildbot, attic, deploy-rs, aragorn, denethor, erebor, ammars-pc]
tags: [deployment, gitops, ci, monitoring, isolation]
---

## Context and Problem Statement

Fleet servers drifted from `main` whenever Buildbot's push deploy skipped a host, raced a local change, or held a fleet-wide SSH key that could activate any PR build. Desktop work needed a fast `nh home switch` loop that must not wait on CI, while released `main` still needed a safe nightly path onto `ammars-pc`. The prior Buildbot post-build deploy coupled evaluation success to root activation and made a PR branch named like a host a latent activation risk.

Plan: `.agents/plans/2026-08-19-comin-buildbot-deployment-flow.md`.

## Decision Drivers

- Separate "build and cache" from "activate on a host"
- Keep Attic as the warm store between CI and pull deploys
- Give every always-on server a single automatic convergence owner
- Keep deploy-rs as the explicit recovery path, not a second scheduler
- Preserve standalone Home Manager and `nh home switch` on `ammars-pc`
- Do not weaken Denethor's Work VLAN isolation beyond a metrics-only pinhole
- Prefer existing packages and Prometheus exporters over new daemons

## Considered Options

1. **Keep Buildbot push deployment** (status quo)
2. **Central Aragorn deploy-rs for every host on a timer**
3. **Native per-host systemd timers that `nixos-rebuild switch --flake`**
4. **Comin everywhere, including the desktop**
5. **Hybrid: Comin on servers, Buildbot+Attic for CI, activity-aware deploy-rs for `ammars-pc`** (chosen)

## Decision Outcome

Chosen option: hybrid. Buildbot evaluates and builds, uploads to Attic, and reports Codeberg status — it never activates a host. Comin on `aragorn`, `boromir`, `samwise`, `theoden`, `rivendell`, `erebor`, and `denethor` polls public Codeberg, substitutes from Attic when possible, switches `main`, and tests `testing-<hostname>`. `ammars-pc` keeps standalone Home Manager; Aragorn deploys it with deploy-rs only when the session is locked/clean. deploy-rs nodes for servers remain for manual recovery after Comin is suspended.

### Consequences

- Good: CI no longer holds a fleet root key; activation requires a host-local Comin agent or an intentional recovery deploy.
- Good: Testing branches exercise one host before `main`; retained boot entries cover reboot-back-to-main.
- Good: Desktop local edits stay fast; nightly deploy skips dirty or unlocked sessions.
- Bad: Comin has no automatic health rollback — operators must reboot to a retained generation or use deploy-rs after suspending Comin.
- Bad: Target-side evaluation on small hosts (Denethor 4 GiB) depends on public Attic hit rates; a remote builder is deferred until measured misses force it.
- Bad: One custom desktop activity gate and textfile metrics live on Aragorn instead of a reusable product.
- Neutral: deploy-rs stays in the flake for recovery and desktop; it is not scheduled against Comin-owned servers.

### Confirmation (acceptance criteria)

These checks have not run yet; confirm each during rollout before relying on the new flow:

- Comin exporters must scrape cleanly (including Denethor via the OPNsense TCP 4243 pinhole and Erebor via Tailscale).
- Buildbot must build and upload without `postBuildSteps` deploy.
- A testing-branch deploy must roll back by reboot to the prior `main` generation.
- A dirty or unlocked desktop must produce a skip metric/ntfy, not an activation.

## Pros and Cons of the Options

### Keep Buildbot push deployment

- Good: Already wired; one place sees build success and activation.
- Bad: Fleet SSH authority on the CI worker; PR code paths can reach root activation; hard to reason about which commit is live on which host.

### Central Aragorn deploy-rs timer

- Good: Reuses existing deploy-rs nodes and magic rollback.
- Bad: Single chokepoint; still push-based; every host trusts Aragorn's scheduler; duplicates what Comin already solves for always-on servers.

### Native per-host systemd timers

- Good: No new dependency; trivial to read.
- Bad: Reimplements polling, branch policy, testing vs switch, retention, and metrics that Comin already provides.

### Comin everywhere (including desktop)

- Good: One tool for all NixOS hosts.
- Bad: Desktop needs activity gates, Wake-on-LAN, and standalone Home Manager ordering that Comin does not model; would fight local `nh home switch` experiments.

### Hybrid (chosen)

- Good: Matches host roles — servers converge from Git, desktop stays interactive, CI stays build-only.
- Bad: Two automatic deploy mechanisms to document; operators must know to suspend Comin before recovery deploy-rs.
