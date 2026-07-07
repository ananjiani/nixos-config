---
date: 2026-07-07
title: Latent glibc collation mismatch blocked paperless DB creation on theoden
severity: low
duration: ~1h
systems: [theoden, postgresql, paperless, nixpkgs]
tags: [database, nixos, collation, glibc]
---

## Summary

Deploying paperless-ngx to theoden failed to start any paperless service. The
root cause was not paperless: a prior nixpkgs glibc bump (2.40 → 2.42) had left
PostgreSQL's `template1` database recording the old collation version. Existing
databases (atticd, buildbot, immich) kept running — postgres only warns on the
mismatch for them — but `CREATE DATABASE paperless` (which clones `template1`)
refuses when the template's recorded collation version differs from what the
OS provides. NixOS's `postgresql-setup.service` exited 1, leaving
`postgresql.target` inactive, which cascaded into every paperless unit
(`paperless-scheduler` requires the target; the web/consumer/task-queue units
bind to the scheduler). Fixed non-disruptively with
`ALTER DATABASE ... REFRESH COLLATION VERSION`; no daemon restart, no impact on
existing services. Action item #1 (auto-refresh before setup) implemented.

## Timeline

All times CDT, 2026-07-07.

- **~12:08** — theoden switched to the new config (paperless module enabled).
  `postgresql-setup.service` runs `CREATE DATABASE paperless`, fails with
  `ERROR: template database "template1" has a collation version mismatch
  (created with 2.40, OS provides 2.42)`. Service exits 1. All four paperless
  units fail with `dependency`.
- **~12:31** — second activation attempt (config re-applied); identical failure.
- **~12:55** — investigation begins. Initial suspicion: vault-agent not
  rendering `/run/secrets/paperless-admin-pw` (the repo's repeat-offender per
  the sops-nix-wipes-vault-agent invariant).
- **~12:57** — checked `/run/secrets/paperless-admin-pw`: present, correct
  owner/mode (paperless:paperless 0400). Vault-agent ruled out.
- **~12:58** — `systemctl --failed` isolated the single failed unit:
  `postgresql-setup.service`. `postgresql.target` inactive despite
  `postgresql.service` active (attic/buildbot/immich still serving).
- **~12:59** — `journalctl -u postgresql-setup` showed the collation mismatch
  error verbatim.
- **~13:03** — applied `ALTER DATABASE ... REFRESH COLLATION VERSION` on
  template1, postgres, atticd, buildbot, immich. template1 changed 2.40→2.42;
  others reported "version has not changed" (already fine).
- **~13:04** — `systemctl restart postgresql-setup.service` → active; `CREATE
  DATABASE paperless` succeeded. Started `postgresql.target` + paperless units.
- **~13:06** — all five paperless services active; `http://theoden:28981`
  returns HTTP 200; `https://paperless.lan` returns HTTP 200 end-to-end.

## What Happened

PostgreSQL records the collation version of each database at creation time in
`pg_database.datcollversion`. Collation (string sort/compare rules, e.g.
`en_US.UTF-8`) is sourced from the C library — glibc on NixOS. When glibc is
updated, the collation rules can (rarely) change, so postgres stamps each DB
with the glibc version it was created under. On `CREATE DATABASE` — which
clones `template1` — postgres compares template1's *recorded* version against
the OS's *current* version and refuses if they differ, because the new DB
would inherit inconsistent sort semantics.

theoden's postgres (pg_16) was created months ago under glibc 2.40. A nixpkgs
update later shipped glibc 2.42. Existing DBs continued running (postgres logs
a warning but does not stop them), so the host looked healthy. The mismatch
sat dormant until paperless became the first *new* database requested since the
bump. `postgresql-setup.service` (NixOS's generated unit that applies
`ensureDatabases`/`ensureUsers`) ran `CREATE DATABASE paperless`, hit the
mismatch, and exited 1 — leaving `postgresql.target` inactive and cascading
into every paperless unit via the `requires`/`bindsTo` chain.

The fix — `ALTER DATABASE <name> REFRESH COLLATION VERSION` — updates the
recorded version stamp to the current OS version. It is non-destructive
(metadata only), requires no daemon restart, and did not disturb attic,
buildbot, or immich.

## Contributing Factors

- **Routine glibc bumps via nixpkgs updates** — on NixOS, a `nixpkgs` input
  bump can advance glibc, silently invalidating postgres's recorded collation
  versions. There is no signal that this happened.
- **Postgres's collation-version safety check** — correct behavior (it guards
  against silent sort-order corruption), but it turns a routine library bump
  into a hard failure for new-DB creation.
- **NixOS `ensureDatabases` assumes `CREATE DATABASE` always succeeds** — the
  generated `postgresql-setup.service` has no pre-flight reconciliation of
  collation versions; a mismatch aborts the whole setup script.
- **Latent by design** — existing DBs are unaffected, so the host appears
  healthy until a *new* DB is requested. No alerting watched
  `postgresql-setup.service` or `postgresql.target`, so the failure only
  surfaced when a deploy depended on it.
- **Symptom misdirection** — paperless services dead pointed at paperless /
  vault-agent / the secret, not at postgres. The dependency chain
  (`scheduler` → `postgresql.target` → `postgresql-setup.service`) was the
  actual signal.

## What I Was Wrong About

- I assumed the failure was vault-agent not rendering the admin password — the
  repo's most common secret-path failure (sops-nix wipes `/run/secrets/*` on
  every deploy). It was correctly rendered; vault-agent was fine.
- I assumed postgres was healthy because attic, buildbot, and immich were
  serving. The *daemon* was healthy; the *setup target* was dead. "Services
  are up" does not mean "the NixOS setup unit that manages DB creation
  succeeded."
- I had no mental model for collation-version tracking as a thing that could
  block `CREATE DATABASE`. It is a postgres safety feature, not a bug — but on
  a distro that bumps glibc routinely, it becomes an operational landmine.

## What Helped

- **`systemctl --failed` + `systemctl list-dependencies paperless-scheduler`**
  isolated the dead dependency (`postgresql-setup.service`) in one step,
  bypassing the paperless-centric misdirection.
- **The vault-agent secret was correctly rendered** — ruled out the usual
  culprit fast, avoiding a detour into sops-nix / rehydrate debugging.
- **The fix was non-destructive** — `REFRESH COLLATION VERSION` is metadata-
  only, no daemon restart, so attic/buildbot/immich saw no disruption.
- **`journalctl` preserved the verbatim error** — postgres named template1,
  the two versions, and the remediation hint (`ALTER DATABASE ... REFRESH
  COLLATION VERSION`) directly.

## What Could Have Been Worse

- If I had "fixed" it by restarting `postgresql.service` to clear state, I
  would have briefly interrupted attic, buildbot, and immich — the lazy fix
  would have been the wrong fix.
- If the glibc collation change had actually altered sort order for indexed
  text columns, indexes could have silently become corrupt; a correct fix
  would also require `REINDEX`. Skipped here (low risk for this homelab's
  data, but worth noting as a known gap).
- If a more critical new database had been needed under time pressure (e.g. a
  production service, not a fresh paperless install), the same latent mismatch
  would have blocked it with no prior warning.
- The mismatch had been latent since the glibc bump — any `ensureDatabases`
  addition on theoden in that window would have failed identically.

## Is This a Pattern?

**Yes — systemic, not a one-off.** The combination NixOS + `services.postgresql`
+ `ensureDatabases` + routine glibc bumps recurs on *every* host running
postgres this way. It is not "fix and move on"; the approach (declarative DB
creation without collation-version reconciliation) needs a systemic mitigation.
Action item #1 below addresses this at the config level so future glibc bumps
self-heal.

## Action Items

1. ✅ **Done** — Add a `preStart` to `postgresql-setup.service` that refreshes
   collation versions for all connectable databases before `ensureDatabases`
   runs `CREATE DATABASE`. Implemented in `hosts/servers/theoden/configuration.nix`.
   Idempotent (matching DBs emit a harmless NOTICE). Future glibc bumps now
   self-heal on the next setup run.
2. **Open** — Alert on `postgresql-setup.service` failed or `postgresql.target`
   inactive. Would have caught this before any deploy depended on it. Currently
   no such alert exists.
3. **Open** — Add a collation-refresh / dump-restore runbook to repo docs.
   Related to the still-open action item in
   `2026-02-04-2030-postgres-major-version-crashloop.md` (document Postgres
   dump/restore procedure).
4. **Consider** — A monitoring check that warns when
   `pg_database.datcollversion <> pg_collation_actual_version(...)` for any DB,
   surfacing latent mismatches before they block a `CREATE DATABASE`.

## Lessons

- "Service X is dead" usually means "X's dependency is dead." Chase the
  dependency chain (`systemctl --failed`, `list-dependencies`), not the symptom
  the ticket names.
- On NixOS, a healthy daemon does not imply a healthy NixOS setup unit. The
  `postgresql.service` was up; `postgresql-setup.service` (the unit that
  applies declarative DB state) was dead. Watch the setup unit, not just the
  daemon.
- Routine library bumps (glibc) can invalidate assumptions baked into
  stateful services (postgres collation stamps). On an immutable, frequently-
  updated distro like NixOS, "what changed underneath the service?" is a
  first-class question.
