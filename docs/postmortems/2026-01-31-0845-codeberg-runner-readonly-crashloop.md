---
date: 2026-01-31
title: Codeberg runner CrashLoopBackOff blocked Flux apps reconciliation
severity: moderate
duration: 45m
systems: [k3s, codeberg-runner, flux]
tags: [kubernetes, forgejo, projected-volume, readonly]
commit: https://codeberg.org/ananjiani/infra/commit/81cb87b
---

## Summary

The Forgejo runner (codeberg-runner) entered CrashLoopBackOff because it tried to write its registration file to `/config/.runner` on a read-only projected volume. This blocked the Flux `apps` kustomization from reconciling for over 30 minutes, preventing other app updates (including the cliproxy fix) from being applied.

## Timeline

- **~07:45 CST** - Noticed Flux `apps` kustomization stuck at old revision with "Reconciliation in progress"
- **08:00** - Identified health check failure: `timeout waiting for: [Deployment/codeberg-runner/codeberg-runner status: 'InProgress']`
- **08:05** - Checked codeberg-runner logs: `Error: failed to save runner config: open /config/.runner: read-only file system`
- **08:10** - First fix attempt: copy config to `/data` emptyDir, point daemon at `/data/config.yaml` - runner still looked for `/config/.runner`
- **08:35** - Second fix attempt: rename projected volume to `config-src`, mount writable emptyDir at `/config`, copy files there in init container
- **08:42** - Runner started successfully: `runner: k8s-runner declared successfully` / `[poller] launched`
- **08:43** - Confirmed 2/2 Running, stable with no new restarts

## What Happened

The codeberg-runner deployment used a projected volume (combining a ConfigMap and a Secret) mounted read-only at `/config`. The runner config specified `runner.file: /data/.runner`, and an init container copied the `.runner` registration file from `/config/.runner` to `/data/.runner`.

The runner binary started fine and successfully registered with the Codeberg instance. But immediately after registration, it tried to save/update the `.runner` file back to `/config/.runner` - the same path where the read-only projected volume was mounted. This write failed with `read-only file system`, crashing the runner.

The first fix attempted to avoid `/config` entirely by pointing the daemon at `/data/config.yaml` and removing the `/config` mount from the runner container. But the runner binary hardcodes `/config/.runner` as the save path regardless of the `runner.file` config setting. With no volume at `/config`, the error changed to `no such file or directory`.

The working fix was to mount a writable emptyDir at `/config` and use an init container to copy both `config.yaml` and `.runner` from a read-only projected source volume (`config-src`) into it. This gives the runner a writable `/config/.runner` to save to.

## Contributing Factors

- The forgejo runner writes to `/config/.runner` on a hardcoded path, ignoring the `runner.file` setting in its config for the save operation
- Projected volumes in Kubernetes are always read-only
- The original deployment had an init container that copied `.runner` to `/data/.runner`, suggesting someone had already worked around a similar issue before, but the runner container still mounted the read-only `/config`
- `kubectl apply` merges rather than replaces, so the first manual fix attempt didn't actually remove the `/config` volume mount from the running pod
- The health check failure on codeberg-runner blocked the entire `apps` kustomization, creating a cascading delay for unrelated app updates

## What I Was Wrong About

- **"The `runner.file` config setting controls where the runner reads and writes"** - It controls where it reads from, but the runner has a hardcoded save path at `/config/.runner` regardless of this setting.
- **"Removing the volume mount removes the path"** - `kubectl apply` is a strategic merge patch. It doesn't remove fields that were previously set. Required `kubectl replace --force` to actually remove the mount.
- **"Copying to /data and pointing --config there avoids the /config path entirely"** - The runner still constructs the `/config/.runner` path independently of the `--config` flag location.

## What Helped

- Adding debug `echo` and `ls -la` commands to the init container immediately showed that files were being copied correctly, isolating the problem to the runner binary's behavior
- The error messages were specific and changed meaningfully between attempts: `read-only file system` vs `no such file or directory` helped narrow down the runner's hardcoded path behavior

## What Could Have Been Worse

- If the Flux `apps` kustomization had a `dependsOn` chain, more kustomizations could have been blocked
- The codeberg-runner was the CI runner - if a critical CI build was needed during this window, it would have been unavailable

## Is This a Pattern?

- [x] One-off: Correct and move on
- [ ] Pattern: Revisit the approach

This is specific to the forgejo runner's hardcoded path behavior. The general lesson about projected volumes being read-only is worth remembering, but most apps respect their own config for file paths.

## Action Items

- [x] Mount writable emptyDir at `/config` with init container copying from read-only projected source
- [x] Update `runner.file` in configmap to `/config/.runner` for consistency
- [ ] Consider adding Flux health check timeout or `dependsOn` configuration to prevent one failing app from blocking all reconciliation

## Lessons

- Forgejo runner hardcodes `/config/.runner` as its save path. The `runner.file` config setting only affects the read path. Don't trust that an app's config fully controls its file I/O paths.
- `kubectl apply` is a merge, not a replace. To remove fields (like volume mounts), use `kubectl replace --force`.
- When a Flux kustomization health check fails on one deployment, it blocks reconciliation for ALL resources in that kustomization. A single broken app can hold up unrelated updates.
