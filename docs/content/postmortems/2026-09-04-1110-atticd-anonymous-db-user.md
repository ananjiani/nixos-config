---
date: 2026-09-04
title: Attic binary cache down after nixpkgs bump — DB user resolved to "anonymous"
severity: moderate
duration: 1h 11m (10:10–11:21 CDT)
systems: [theoden, erebor, attic, postgresql, buildbot, comin, gatus, ntfy]
tags: [nixos, attic, postgres, nixpkgs-bump, comin, alert-fatigue]
commit: https://codeberg.org/ananjiani/infra/commit/09f895f062cc744ae60475874ca7caac551939df
---

## Summary

A nixpkgs jump (`20260612` → `20260829`) deployed by comin rebuilt `attic` with a newer sqlx/whoami stack. Under the service's `DynamicUser` + `PrivateUsers` sandbox, the username lookup failed silently and sqlx connected as database user `anonymous`. Postgres peer auth rejected it, atticd crash-looped, and the binary cache was unreachable for 1h 11m. Gatus detected the outage and sent an ntfy alert within three minutes, but routine alert noise hid the valid alert.

## Timeline

All times CDT, 2026-09-04.

- **10:09** - Comin fetches new commits; evaluates generation for `09f895f0` (a Renovate PR bumping the forgejo runner Docker tag)
- **10:10:34** - Comin deploys gen 9: `nixos-system-theoden-26.11.20260829.e8be781` (previous gen 8, deployed Sep 2, was `26.11.20260612.49a4bd0`)
- **10:10:37** - Switch restarts `atticd`; it exits with `Peer authentication failed for user "anonymous"` and enters a crash-loop (systemd 10s restart backoff)
- **10:10:57** - Gatus records the first failed Attic check
- **10:12:58** - The third failed check triggers an ntfy alert for Attic. Buildbot and voicemail alerts fire at nearly the same time and resolve two minutes later
- **10:57** - Investigation begins after a manual status check; restart counter at 261. The earlier alert was lost among routine monitoring noise
- **11:00** - Root cause identified; fix (pin `user=atticd` in the DB URL) validated live on theoden via `systemd-run` with the exact sandbox flags — migrations ran, API listened on `[::]:8080`
- **11:02** - PR #285 opened with the one-line fix
- **11:18** - PR #285 merged; comin deploys the fixed generation
- **11:21:58** - Gatus records the second successful check and sends the resolved ntfy alert

## What Happened

Comin deployed a routine Renovate merge to `main`. The PR itself only bumped a Docker tag, but the deploy was the first theoden build against a freshly merged nixpkgs input (`20260612` → `20260829`, ~2.5 months of nixpkgs). The rebuild replaced the `attic-server` derivation (store path changed), pulling in a newer sqlx/whoami.

The atticd database URL was `postgresql:///atticd?host=/run/postgresql` — no `user` parameter. The old binary resolved the connecting user from the process identity, which landed on `atticd`, and Postgres peer auth (local socket, OS user == DB user) accepted it. The new binary, running under `DynamicUser=true` + `PrivateUsers=true` (both present before and after — the unit did not change), can no longer resolve its username through that sandbox. whoami's fallback chain yields the literal string `anonymous`, sqlx sends it as the DB user, and peer auth rejects it with `Peer authentication failed for user "anonymous"`.

Comin's deploy succeeded from its point of view: `switch-to-configuration` completed, and the system booted the new generation. Comin does not health-check individual services, so a crash-looping unit does not fail or roll back a deploy.

Gatus on erebor did health-check the public Attic endpoint every minute. It detected the first failure at 10:10:57 and sent an ntfy alert after the third failure at 10:12:58. The alert path worked. The response path did not: all external checks use the same `monitoring` topic, priority, and generic description. Buildbot and voicemail also fired transient alerts at the same time. The real Attic outage blended into routine noise, so work began only after a manual status check.

## Contributing Factors

- A ~2.5-month nixpkgs jump reached theoden inside an unrelated, harmless-looking PR; nothing in the PR description hinted the system closure would change
- `DynamicUser` + `PrivateUsers` hide the process username from whoami; the new dependency stack degrades to a *silent wrong value* (`anonymous`) instead of a loud failure
- The DB URL never pinned `user=`, so correctness depended on ambient username resolution inside a sandbox
- Comin verifies activation, not service health; a crash-looping unit after a successful switch does not stop or roll back the deploy
- External checks share one noisy ntfy route with the same priority and generic description; transient alerts trained the notification channel to be ignored

## What I Was Wrong About

- "A Renovate PR for a Docker tag can't break system services." Wrong — the *next deploy after an input bump* rebuilds everything; the PR that merges the bump and the PR that carries it to a host are often different
- "`postgresql:///atticd?host=/run/postgresql` is a complete connection string." It was complete only by coincidence of how the old binary resolved the user. The implicit dependency was invisible until a dependency update changed the resolution behavior
- "No human response means no monitor fired." Wrong — Gatus detected the outage quickly and sent the alert. Alert fatigue, not missing coverage, delayed the response

## What Helped

- Gatus kept an exact external timeline: first failure at 10:10:57, alert at 10:12:58, and recovery at 11:21:58
- Comin keeps previous generations: gen 8 (known-good, Sep 2) was one `switch-to-configuration` away the entire time
- `journalctl -u atticd` plus systemd's restart counter pinned the onset to the exact deploy at 10:10, which pointed straight at the generation diff
- `systemd-run` with the real unit's sandbox flags (`DynamicUser=yes`, `User=atticd`, `PrivateUsers=yes`) let the fix be proven against the *new* binary before touching the repo — the PR was validated, not guessed

## What Could Have Been Worse

- Buildbot workers only lost cache hits (slower builds), they didn't fail — if any closure had depended on the cache as the sole substituter, CI would have hard-failed
- The same alert fatigue can hide a more important outage for much longer; monitoring coverage does not help when every notification looks equally urgent
- The same class of silent behavior change could have hit a service with worse failure modes (the postgres major-version crashloop of 2026-02-04 was the same shape: nixpkgs bump, service crash-loop after deploy)

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This incident shows two patterns. First, big input jumps can change runtime behavior when they reach a host through an unrelated PR (see `2026-02-04-2030-postgres-major-version-crashloop.md`; the Nvidia driver-bump invariant in AGENTS.md is another example). Second, monitoring coverage is not the gap here: Gatus worked. The gap is signal quality. One flat, noisy alert stream makes important and routine failures look the same.

## Action Items

- [x] Merge PR #285, pin `user=atticd`, and confirm `https://attic.dimensiondoor.xyz/middle-earth/nix-cache-info` returns HTTP 200
- [x] Confirm the existing Gatus check detected the outage and sent trigger and recovery alerts
- [x] Audit `postgresql:///` URLs; Attic was the only peer-auth URL in the repo, and it now pins the user
- [ ] Review seven days of the `monitoring` topic; list the checks that create the most alerts and mark each alert actionable or routine
- [ ] Tune the existing checks from that list: give important alerts a distinct ntfy route or priority, and make noisy non-critical checks wait through longer transient failures

Automatic rollback is not an action item for Attic. A cache outage slows builds but does not lose data. Rolling back on a transient network or Cloudflare failure adds more risk than it removes.

## Lessons

- Pin `user=` (and any identity the auth scheme depends on) in every connection string that relies on peer auth — ambient identity under systemd sandboxing is not stable across dependency updates
- Alert coverage is not enough. A useful alert must stand apart from routine noise and tell the reader what matters
- When a deploy's nixpkgs jumps months at once, the diff that matters is the derivation diff, not the PR diff — check what actually rebuilt
- A live external check can catch runtime failures that a Nix build cannot; automatic rollback still needs an impact-based decision
- Validate a fix against the failing binary in the failing sandbox before opening the PR: `systemd-run --property=DynamicUser=yes --property=User=<u> --property=PrivateUsers=yes` reproduces the unit's identity behavior in one command
