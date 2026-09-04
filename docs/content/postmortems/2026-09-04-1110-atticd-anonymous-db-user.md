---
date: 2026-09-04
title: Attic binary cache down after nixpkgs bump — DB user resolved to "anonymous"
severity: moderate
duration: ~1h+ (10:10 CDT until PR #285 deploys)
systems: [theoden, attic, postgresql, buildbot, comin]
tags: [nixos, attic, postgres, nixpkgs-bump, comin]
commit: https://codeberg.org/ananjiani/infra/commit/09f895f062cc744ae60475874ca7caac551939df
---

## Summary

A nixpkgs jump (`20260612` → `20260829`) deployed by comin rebuilt `attic` with a newer sqlx/whoami stack. Under the service's `DynamicUser` + `PrivateUsers` sandbox, the username lookup now fails silently and sqlx connects as database user `anonymous`. Postgres peer auth rejects it, atticd crash-loops, and the binary cache at `theoden.lan:8080` was unreachable for all hosts.

## Timeline

All times CDT, 2026-09-04.

- **10:09** - Comin fetches new commits; evaluates generation for `09f895f0` (a Renovate PR bumping the forgejo runner Docker tag)
- **10:10:34** - Comin deploys gen 9: `nixos-system-theoden-26.11.20260829.e8be781` (previous gen 8, deployed Sep 2, was `26.11.20260612.49a4bd0`)
- **10:10:37** - Switch restarts `atticd`; it exits with `Peer authentication failed for user "anonymous"` and enters a crash-loop (systemd 10s restart backoff)
- **~10:10–10:57** - Cache silently down for ~47 minutes. Builds on all hosts fall back to building from source; nothing alerts
- **10:57** - Investigation begins after a manual status check; restart counter at 261
- **11:00** - Root cause identified; fix (pin `user=atticd` in the DB URL) validated live on theoden via `systemd-run` with the exact sandbox flags — migrations ran, API listened on `[::]:8080`
- **11:02** - PR #285 opened with the one-line fix
- **Pending** - Merge + comin deploy restores the cache

## What Happened

Comin deployed a routine Renovate merge to `main`. The PR itself only bumped a Docker tag, but the deploy was the first theoden build against a freshly merged nixpkgs input (`20260612` → `20260829`, ~2.5 months of nixpkgs). The rebuild replaced the `attic-server` derivation (store path changed), pulling in a newer sqlx/whoami.

The atticd database URL was `postgresql:///atticd?host=/run/postgresql` — no `user` parameter. The old binary resolved the connecting user from the process identity, which landed on `atticd`, and Postgres peer auth (local socket, OS user == DB user) accepted it. The new binary, running under `DynamicUser=true` + `PrivateUsers=true` (both present before and after — the unit did not change), can no longer resolve its username through that sandbox. whoami's fallback chain yields the literal string `anonymous`, sqlx sends it as the DB user, and peer auth rejects it with `Peer authentication failed for user "anonymous"`.

Comin's deploy succeeded from its point of view: `switch-to-configuration` completed, the system booted the new generation. Comin does not health-check individual services, so a crash-looping unit does not fail or roll back a deploy. The cache stayed down until a human asked for a status check.

## Contributing Factors

- A ~2.5-month nixpkgs jump reached theoden inside an unrelated, harmless-looking PR; nothing in the PR description hinted the system closure would change
- `DynamicUser` + `PrivateUsers` hide the process username from whoami; the new dependency stack degrades to a *silent wrong value* (`anonymous`) instead of a loud failure
- The DB URL never pinned `user=`, so correctness depended on ambient username resolution inside a sandbox
- Comin verifies activation, not service health; a crash-looping unit after a successful switch is invisible to it
- No alerting on atticd health or cache reachability; detection depended on a human checking

## What I Was Wrong About

- "A Renovate PR for a Docker tag can't break system services." Wrong — the *next deploy after an input bump* rebuilds everything; the PR that merges the bump and the PR that carries it to a host are often different
- "`postgresql:///atticd?host=/run/postgresql` is a complete connection string." It was complete only by coincidence of how the old binary resolved the user. The implicit dependency was invisible until a dependency update changed the resolution behavior

## What Helped

- Comin keeps previous generations: gen 8 (known-good, Sep 2) was one `switch-to-configuration` away the entire time
- `journalctl -u atticd` plus systemd's restart counter pinned the onset to the exact deploy at 10:10, which pointed straight at the generation diff
- `systemd-run` with the real unit's sandbox flags (`DynamicUser=yes`, `User=atticd`, `PrivateUsers=yes`) let the fix be proven against the *new* binary before touching the repo — the PR was validated, not guessed

## What Could Have Been Worse

- Buildbot workers only lost cache hits (slower builds), they didn't fail — if any closure had depended on the cache as the sole substituter, CI would have hard-failed
- Detection could have taken days instead of ~1h; nothing in the stack would have noticed
- The same class of silent behavior change could have hit a service with worse failure modes (the postgres major-version crashloop of 2026-02-04 was the same shape: nixpkgs bump, service crash-loop after deploy)

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This is the second incident where a nixpkgs bump changed a service's runtime behavior silently (see `2026-02-04-2030-postgres-major-version-crashloop.md`). The recurring gap is the same: big input jumps land on hosts through unrelated PRs, and nothing smoke-checks services after activation. The Nvidia driver-bump invariant in AGENTS.md is a third instance of the same class.

## Action Items

- [ ] Merge PR #285 (pins `user=atticd`); confirm with `curl http://theoden.lan:8080/nix-cache-info`
- [ ] Add an atticd health check (uptime probe on `:8080/nix-cache-info` or systemd `OnFailure=` notify) so a crash-loop pages instead of waiting for a human
- [ ] Consider a post-deploy smoke check in comin's flow (or a systemd unit-level watchdog) so failed *services* roll back or alert, not just failed switches
- [ ] Audit other peer-auth DB URLs in the repo for the same implicit-user dependency (grep `postgresql:///`)

## Lessons

- Pin `user=` (and any identity the auth scheme depends on) in every connection string that relies on peer auth — ambient identity under systemd sandboxing is not stable across dependency updates
- When a deploy's nixpkgs jumps months at once, the diff that matters is the derivation diff, not the PR diff — check what actually rebuilt
- A deploy system that only verifies activation needs *something* watching service health, or every latent crash-loop ships to production quietly
- Validate a fix against the failing binary in the failing sandbox before opening the PR: `systemd-run --property=DynamicUser=yes --property=User=<u> --property=PrivateUsers=yes` reproduces the unit's identity behavior in one command
