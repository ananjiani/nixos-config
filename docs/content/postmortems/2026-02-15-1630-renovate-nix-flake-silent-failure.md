---
date: 2026-02-15
title: Renovate silently skipping all Nix flake input updates
severity: minor
duration: unknown (weeks to months)
systems: [renovate, k3s, codeberg]
tags: [renovate, nix, ci-cd, kubernetes]
commit: https://codeberg.org/ananjiani/infra/commit/eaa6ecd
---

## Summary

Renovate's self-hosted CronJob was detecting all 33 Nix flake inputs but silently failing to create update PRs for any of them. The nix manager's per-input version resolution returned empty results for every input because most flake inputs track branches (not semver tags). This went unnoticed for an unknown period. The fix required enabling `lockFileMaintenance` (which runs `nix flake update` directly) and switching to the `renovate/renovate:full` image (which ships the `nix` binary pre-installed).

## Timeline

- **Unknown** - Renovate nix manager enabled with `"nix": { "enabled": true }` and a package rule to group and automerge all flake input updates
- **Unknown** - Nix flake PRs never appeared on Codeberg; other managers (Docker, Terraform, Forgejo actions, Ansible regex) continued working normally
- **2026-02-15 ~15:30** - Noticed no flake update PRs while reviewing Codeberg PR list
- **2026-02-15 ~15:45** - SSH'd into boromir, pulled logs from the most recent Renovate job (`kubectl logs -n renovate job/renovate-29519220`)
- **2026-02-15 ~15:50** - Found 32 instances of `"Found no results from datasource that look like a version"` with empty `releases: []` for every flake input including nixpkgs
- **2026-02-15 ~16:00** - Researched Renovate GitHub discussions; discovered that per-input version tracking doesn't work for branch-tracking inputs, and `lockFileMaintenance` is the intended mechanism
- **2026-02-15 ~16:10** - Added `lockFileMaintenance` to `renovate.json`, switched image from `renovate/renovate:latest` to `renovate/renovate:full`, pushed to Codeberg
- **2026-02-15 ~16:15** - First manual test: lockFileMaintenance didn't run — its default schedule is "before 5am on Monday" and it was Saturday
- **2026-02-15 ~16:20** - Temporarily set schedule to `"at any time"`, triggered second manual run
- **2026-02-15 ~16:48** - PR #40 `"chore(deps): lock file maintenance"` created on Codeberg — confirmed working
- **2026-02-15 ~16:55** - Set final schedule to `"before 6am every day"` to match the CronJob schedule

## What Happened

The Renovate CronJob was deployed to the k3s cluster with `"nix": { "enabled": true }` and a package rule grouping all nix flake inputs for automerge. Renovate successfully extracted 33 dependencies from `flake.nix`/`flake.lock` on every run.

However, the nix manager's per-input approach tries to look up each flake input as a versioned dependency — querying GitHub for semver-like releases or tags. The vast majority of Nix ecosystem repos (nixpkgs, home-manager, disko, sops-nix, etc.) don't use semver releases. They track branches where the "version" is a git commit hash. The datasource returned empty `releases: []` for all 32 unique inputs, and Renovate logged this as an INFO-level message and moved on. No errors, no warnings — just silence.

The correct mechanism for updating branch-tracking flake inputs is `lockFileMaintenance`, which delegates to `nix flake update` to refresh the entire lock file. This also requires the `nix` binary to be available in the container, which the `latest` (slim) image doesn't include — the `full` image does.

## Contributing Factors

- **Renovate's nix manager silently produces no output when per-input resolution fails** — the "Found no results from datasource" message is INFO-level, not a warning, making it easy to miss
- **The nix manager was reworked (v39.147.0) to treat all flake inputs as dependencies**, but this approach fundamentally doesn't work for the majority of flake inputs that track branches rather than tagged releases
- **`lockFileMaintenance` is not enabled by default** — the `config:recommended` preset does not include it, so it must be explicitly enabled
- **`lockFileMaintenance` has its own internal schedule** (default: "before 5am on Monday") independent of the CronJob schedule, which complicated testing
- **The `latest` image lacks the `nix` binary** — even with lockFileMaintenance enabled, the slim image can't execute `nix flake update` (though `binarySource=install` might download it at runtime, this adds another failure point)

## What I Was Wrong About

- **"Enabling the nix manager with a grouping rule is sufficient for flake updates"** — the per-input version tracking and the `lockFileMaintenance` approach are two completely different mechanisms. The former works for tagged releases; the latter is what's needed for branch-tracking inputs.
- **Initial hypothesis was wrong: "the `latest` image doesn't have nix, use `full`"** — while switching to `full` was correct for reliability, the actual blocker was that `lockFileMaintenance` wasn't enabled at all. The image alone wouldn't have fixed anything.

## What Helped

- The Renovate logs clearly showed `"Found no results from datasource that look like a version"` for every input, making the diagnosis straightforward once we looked
- Other managers (Docker, Terraform, etc.) working correctly proved the CronJob, credentials, and Codeberg integration were fine — isolating the problem to the nix manager specifically
- `kubectl create job --from=cronjob/renovate` enabled fast iteration without waiting for the 5am schedule

## What Could Have Been Worse

- If `lockFileMaintenance` updated only the lock file without the nix binary present, it could have produced a broken `flake.lock` and merged it via automerge — potentially breaking CI for all hosts
- The flake inputs being stale for an unknown period meant security patches in nixpkgs weren't flowing in automatically, though manual `nix flake update` runs likely happened independently

## Is This a Pattern?

- [x] Pattern: Revisit the approach

**Silent failures in automation are a recurring theme.** Tools that log informational messages instead of warnings/errors when they can't do their job create blind spots. This is similar to how Tailscale silently degraded networking on rivendell — the system technically worked, just not as expected.

Going forward, consider adding alerting for "Renovate ran but created 0 PRs for nix manager" or similar negative-space monitoring.

## Action Items

- [x] Enable `lockFileMaintenance` in `renovate.json`
- [x] Switch to `renovate/renovate:full` image in CronJob
- [x] Set daily schedule for lock file maintenance
- [x] Verify PR creation with manual test run
- [ ] Consider removing the nix package rule grouping if lockFileMaintenance already batches all lock file changes into one PR
- [ ] Add monitoring/alerting for Renovate runs that detect nix deps but create no PRs

## Lessons

- **Renovate's nix manager has two modes**: per-input version tracking (works for tagged repos) and `lockFileMaintenance` (works for branch-tracking repos like most of the Nix ecosystem). For a typical NixOS flake with 30+ inputs, you almost certainly need `lockFileMaintenance`.
- **Always check the logs when automation isn't producing expected output** — the diagnosis took minutes once we looked at `kubectl logs`. The delay was in noticing the absence of PRs in the first place.
- **Beta features in Renovate may have non-obvious prerequisites** — the nix manager docs don't prominently mention that `lockFileMaintenance` is effectively required for most real-world flake configurations.
- **`lockFileMaintenance` has its own schedule** independent of the CronJob — test with `"schedule": ["at any time"]` and revert after confirming.
