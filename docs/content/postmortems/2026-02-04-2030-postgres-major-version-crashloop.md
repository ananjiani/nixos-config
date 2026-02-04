---
date: 2026-02-04
title: Postgres v18 major upgrade broke Comet Stremio addon for 19 hours
severity: moderate
duration: ~19h
systems: [k3s, stremio, postgres, renovate]
tags: [kubernetes, database, dependency-management]
---

## Summary

Renovate bumped the Postgres Docker image from v17 to v18 in the Stremio namespace. PostgreSQL refused to start because the on-disk data format is incompatible across major versions. Postgres entered CrashLoopBackOff (238 restarts over 19 hours), which took down Comet — the Stremio torrent addon — since it couldn't connect to its database. All torrent searches returned empty results.

## Timeline

- **~01:00** - Renovate PR "chore(deps): update postgres docker tag to v18" merged into main
- **~01:05** - Flux reconciles, Postgres pod restarts with `postgres:18.1-alpine` image
- **~01:05** - Postgres immediately crashes: `FATAL: database files are incompatible with server — The data directory was initialized by PostgreSQL version 17, which is not compatible with this version 18.1`
- **~01:05** - Comet starts logging `ConnectionRefusedError: [Errno 111]` on every request
- **~01:05–20:00** - Postgres in CrashLoopBackOff, accumulating 238 restarts. Comet running but non-functional (no torrent results)
- **~20:00** - Noticed Comet not returning results, asked HolmesGPT to investigate
- **~20:15** - HolmesGPT identified Postgres CrashLoopBackOff and the version mismatch via Loki logs and pod describe
- **~20:20** - Reverted image to `postgres:17-alpine` in `postgres-statefulset.yaml`, added Renovate guard rule
- **~20:25** - Pushed changes, forced Flux reconcile, deleted crashing pod
- **~20:25** - Postgres started cleanly with 0 restarts, Comet reconnected immediately

## What Happened

Renovate detected that `postgres:18.1-alpine` was available and created a PR to bump from v17. The PR was merged manually without considering that PostgreSQL major versions change the on-disk data format. Unlike most container images where "newer = better," Postgres major upgrades require an explicit data migration step — either `pg_upgrade` or a full dump/restore cycle.

Once the pod restarted with the v18 image, it found v17 data files in the persistent volume and refused to start. The CrashLoopBackOff went unnoticed for 19 hours because there was no alerting on Stremio namespace health, and the failure only manifested as empty search results in Stremio (easy to miss or attribute to other causes).

HolmesGPT was used to investigate and quickly traced the Comet `ConnectionRefusedError` back to the Postgres pod crash, identifying the exact version mismatch from Loki logs.

## Contributing Factors

- **Renovate treats Postgres like any other image** — it has no awareness that major version bumps require data migration for stateful services
- **No Renovate package rule** to prevent or flag Postgres major version bumps differently
- **PR was merged without reviewing what a Postgres major upgrade entails** — the PR title "update postgres docker tag to v18" looks routine
- **No alerting on pod health in the stremio namespace** — 238 restarts over 19 hours went unnoticed
- **Comet's failure mode is silent** — it doesn't crash when the DB is down, it just returns empty results, which is easy to dismiss

## What I Was Wrong About

- I assumed Renovate dependency bumps for container images are safe to merge without investigation. For stateless services this is true, but **stateful services with on-disk format changes are a different category entirely**. The mental model of "container images are interchangeable" breaks for databases.
- I assumed I'd notice quickly if something in the Stremio stack broke. In reality, 19 hours passed because empty search results aren't alarming enough to trigger investigation.

## What Helped

- **HolmesGPT** was able to investigate autonomously — it checked pod status, queried Loki for error logs, and identified the exact root cause without manual kubectl debugging
- **Loki log aggregation** preserved the Postgres error messages even across 238 crash restarts
- **The PVC data was never corrupted** — Postgres v18 refused to start rather than attempting to read incompatible data, so reverting to v17 was a clean fix with no data loss
- **Flux GitOps** meant the fix was just a one-line image tag change, push, and reconcile

## What Could Have Been Worse

- If Postgres v18 had *partially* started and attempted to read v17 data, the persistent volume could have been corrupted, requiring a full data restore
- If this had been a more critical database (not just torrent cache metadata), 19 hours of downtime would have been much more impactful
- If the CrashLoopBackOff had somehow caused resource pressure on the node, other workloads could have been affected

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Renovate will do this for **any** stateful service with major version incompatibilities. This isn't just a Postgres problem — the same applies to:

- MySQL/MariaDB major versions
- Redis major versions (though less often breaking)
- Elasticsearch major versions
- Any database with persistent volumes

The approach of "merge Renovate PRs for container bumps" needs a carve-out for stateful services.

## Action Items

- [x] Revert Postgres image to `17-alpine` in `postgres-statefulset.yaml`
- [x] Add Renovate `packageRule` to block major version automerge for Postgres (creates PR with `manual-upgrade-required` label instead)
- [ ] Audit other stateful services in k8s for the same Renovate risk (Redis, any other databases)
- [ ] Add Prometheus alert for pods in CrashLoopBackOff in the stremio namespace
- [ ] Document the Postgres major upgrade procedure (dump/restore steps) in the repo

## Lessons

- **Stateful services are not like stateless services for dependency updates.** A container image bump that changes on-disk format is a migration, not an upgrade.
- **Renovate PRs for databases deserve extra scrutiny.** The PR title "update postgres docker tag" makes it look routine, but major version bumps for databases are anything but.
- **Silent failures need proactive alerting.** If the only symptom is "search results are empty," you won't notice for hours or days.
- **HolmesGPT is genuinely useful for this kind of investigation** — it correlated the Comet connection errors with the Postgres crashloop faster than manual debugging would have.
