---
date: 2026-01-31
title: Bifrost 503 outage — Helm chart v2.0.0 auto-upgrade rendered no Deployment
severity: moderate
duration: ~33m (bifrost down), ~3h (openclaw config churn)
systems: [bifrost, openclaw, cliproxy, k3s, flux]
tags: [kubernetes, helm, flux, chart-upgrade, sqlite, virtual-keys, openclaw]
commit: https://codeberg.org/ananjiani/infra/commit/6288eb9
---

## Summary

Bifrost (the LLM API gateway on k3s) went down with 503 errors after Flux auto-upgraded the Helm chart from v1.7.0 to v2.0.0 due to an unpinned version constraint (`>=1.0.0`). The v2.0.0 chart has a bug where the Deployment template is conditionally skipped for sqlite+persistence configurations, expecting a StatefulSet template that does not exist in the chart. The result was a namespace with a Service and Ingress but zero pods. Virtual keys stored in the SQLite database were lost when the old PVC was cleaned up. A separate but related issue with Openclaw's setup script destructively overwriting gateway config on every restart compounded the debugging session.

## Timeline

All times CST.

- **~23:55 (Jan 30)** - Openclaw service restarts on pippin; setup script overwrites gateway config, losing `trustedProxies` and `mode` settings
- **~00:26** - WebSocket errors begin: "invalid connect params: at /client/id: must be equal to constant" every ~15 seconds from browser at clawd.dimensiondoor.xyz
- **~01:08** - Telegram plugin config validation errors: "must NOT have additional properties" blocking config reloads
- **~01:25** - Investigation begins. Telegram plugin uses `emptyPluginConfigSchema()` but config contained an `accounts` block
- **~01:30** - Manually fixed telegram config to `{}`, set `gateway.mode=local`, `chmod 700` on state dir
- **~01:35** - `openclaw doctor --fix` runs successfully with 0 errors
- **~02:37** - Openclaw crashes and restarts; old setup script (not yet deployed) overwrites fixes again
- **~02:43** - Deployed updated Nix config to pippin with fixed setup script. Openclaw running cleanly
- **~02:44** - Gateway listening, Telegram connected (@d43m0n_bot), but WebSocket now shows "unauthorized: gateway token missing" (progress — client ID issue resolved)
- **~06:47** - User reports 503 from Bifrost when messaging openclaw on Telegram
- **~06:48** - Confirmed bifrost.dimensiondoor.xyz returning 503
- **~06:49** - Found bifrost namespace has Service and Ingress but no pods
- **~06:50** - HelmRelease says "upgrade succeeded" but chart version went from 1.7.0 to 2.0.0
- **~06:52** - `helm get manifest` shows only ServiceAccount, ConfigMap, Service — no Deployment
- **~06:55** - Downloaded chart v2.0.0 templates. Found the bug: deployment.yaml sets `$useStatefulSet` to true when `storage.mode=sqlite` + `persistence.enabled=true` + no `existingClaim`, then wraps the entire Deployment in `if not $useStatefulSet`. No StatefulSet template exists in the chart. Zero workload objects rendered.
- **~07:00** - Created external PVC (`bifrost-data`), updated HelmRelease with `existingClaim: bifrost-data`, pinned chart to `2.0.0`, fixed ingress schema (`ingress.main.enabled` changed to `ingress.enabled` in v2)
- **~07:05** - Flux couldn't reach Codeberg (transient egress issue from source-controller pod). Applied PVC manually, patched HelmRelease directly.
- **~07:08** - Bifrost pod running, returning 200
- **~07:15** - Discovered virtual keys lost — they were in the SQLite DB, old PVC gone. Added default virtual key declaratively under `governance.virtualKeys`
- **~07:20** - Virtual key working, bifrost fully operational
- **~07:25** - Codeberg reachable again, Flux synced to latest commit

## What Happened

Two interleaved issues created a long night of debugging.

The first issue was Openclaw on pippin. Its setup script ran on every service restart and replaced the gateway configuration file entirely rather than merging new values into existing config. This meant any runtime settings — `trustedProxies`, `gateway.mode`, Telegram plugin state — were wiped on every restart. Making it worse, the Telegram plugin config had a stale `accounts` block that violated the plugin's empty config schema, causing validation failures on every config reload. Fixing this required deploying an updated Nix configuration to pippin with a setup script that merges config and sanitized plugin configuration.

The second, more impactful issue was Bifrost. The HelmRelease used a version constraint of `>=1.0.0`, which allowed Flux to auto-upgrade from v1.7.0 to v2.0.0. The chart's v2.0.0 deployment template has a conditional that calculates whether to use a StatefulSet based on `storage.mode`, `persistence.enabled`, and `existingClaim`. With the existing values (sqlite mode, persistence enabled, no explicit claim), the variable `$useStatefulSet` evaluated to true, causing the Deployment template to be skipped. But the chart does not include a StatefulSet template — it simply does not exist. Helm rendered the release with only a ServiceAccount, ConfigMap, and Service. No pods were created.

Helm reported the upgrade as successful because from Helm's perspective the release was installed without error. There is no built-in validation that a release produces any workload objects. Flux similarly reported the reconciliation as successful.

The fix required three changes: creating an external PVC and setting `existingClaim` (which makes `$useStatefulSet` false, restoring the Deployment), pinning the chart version to prevent future auto-upgrades, and updating the ingress schema to match v2.0.0's changed API. A transient Codeberg connectivity issue from the source-controller pod prevented Flux from pulling the fix, so the HelmRelease was patched directly on the cluster.

After Bifrost came back, the virtual keys that had been configured through the dashboard were gone — they lived only in the SQLite database whose PVC was cleaned up during the upgrade. The key value was recovered from SOPS-encrypted secrets and added declaratively to the HelmRelease values.

## Contributing Factors

- **Unpinned chart version constraint** (`>=1.0.0`) allowed Flux to auto-upgrade across a major version boundary without any review gate.
- **Chart v2.0.0 has a bug**: the Deployment template is conditionally skipped for sqlite+persistence configurations, but the expected StatefulSet template does not exist.
- **Helm does not validate that releases produce workload objects.** An upgrade that renders zero pods is reported as successful.
- **Virtual keys were stored only in the SQLite database**, not declared in configuration. When the PVC lifecycle changed during the upgrade, they were lost.
- **Ingress schema changed silently** in v2.0.0 (`ingress.main.enabled` became `ingress.enabled`), contributing to the broken state.
- **Openclaw's setup script was destructive**: it replaced gateway config on every restart instead of merging, requiring re-fixing after every crash.
- **Telegram plugin config had a stale `accounts` block** that violated the empty schema, causing validation errors that blocked config reloads.

## What I Was Wrong About

- **Assumed `>=1.0.0` was safe because semver major bumps would be caught by review.** Flux auto-reconciles on a schedule. There is no review gate between "new chart version available" and "upgrade applied to the cluster." Semver awareness has to be encoded in the version constraint itself.
- **Assumed "Helm upgrade succeeded" meant the workload was running.** Helm validates template rendering and API object creation, not that those objects result in running pods. A release with zero Deployments and zero StatefulSets is considered successful.
- **Assumed virtual keys configured through the dashboard were durable.** They were persisted to SQLite, but the PVC's lifecycle was not guaranteed across chart major-version upgrades. Dashboard-configured state that is not also declared in version control is ephemeral.
- **Assumed the Openclaw setup script was idempotent.** It was actually destructive — full replacement rather than merge. Every restart was a clean-slate rewrite that lost runtime state.

## What Helped

- **The ConfigMap was still rendered correctly**, so provider configuration (API keys, endpoints) survived the upgrade. Only the workload and virtual keys were affected.
- **The old virtual key value was in SOPS-encrypted secrets.yaml**, making recovery straightforward.
- **`helm template` with minimal values** quickly confirmed the chart bug locally — no need to deploy test releases to the cluster.
- **Direct HelmRelease patching** worked around the Flux/Codeberg connectivity issue, avoiding a longer outage while waiting for egress to recover.
- **Samwise stayed up** through the entire incident, keeping the API server accessible.

## What Could Have Been Worse

- If the chart had also changed the ConfigMap schema, the provider API keys and endpoints could have been lost or misconfigured, breaking all downstream services (cliproxy, openclaw) even after the Deployment was restored.
- If the virtual key value had not been in SOPS secrets, it would have been unrecoverable, requiring regeneration and reconfiguration of every downstream consumer.
- If Codeberg had been down longer, there would have been no way to push fixes through Flux. Direct patching worked for this case, but a more complex fix (multiple resources, CRDs) would have been much harder to apply manually.
- If this had happened during a period without SSH access to the cluster, the 503 could have persisted indefinitely — there is no alerting for "bifrost has zero pods."

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Two patterns are visible here:

**Unpinned dependencies in GitOps.** This is the same class of problem as unpinned package versions in any dependency manager. Flux + unpinned chart constraints means any upstream release is automatically deployed to production. Every HelmRelease should pin to an exact version or at minimum use a `~` (patch-only) constraint, with version bumps handled through explicit commits.

**Stateful configuration managed through dashboards.** Virtual keys, runtime settings, and plugin configs that exist only in application databases or on-disk state are invisible to the GitOps workflow and fragile across upgrades. Anything that matters should be declared in the HelmRelease values or a ConfigMap.

## Action Items

- [x] Pin bifrost chart version to `2.0.0` (commit 6288eb9)
- [x] Create external PVC (`bifrost-data`) with `existingClaim` to work around the chart bug
- [x] Add default virtual key declaratively in HelmRelease values (commit 631da7a)
- [x] Fix openclaw setup script to merge gateway config instead of replacing
- [x] Sanitize telegram plugin config in setup script
- [x] Fix k3s.nix statix warning (repeated systemd blocks)
- [ ] Audit all HelmReleases for unpinned version constraints and pin to exact versions
- [ ] Add a cluster health alert for namespaces with Services/Ingresses but zero running pods
- [ ] File upstream issue on the bifrost chart for the missing StatefulSet template
- [ ] Deploy Gatus for uptime/synthetic monitoring of external endpoints (bifrost, clawd, etc.) with ntfy alerts
- [ ] Configure Flux notification-controller to send reconciliation failures to ntfy
- [ ] Add `spec.healthChecks` to HelmReleases to verify Deployments have ready pods before marking release as successful
- [ ] Evaluate kube-state-metrics + Prometheus alerting for structural k8s issues (zero-replica deployments, unbound PVCs, crashlooping pods)

## Observability Gaps

This incident exposed several monitoring blind spots. The bifrost 503 was only discovered when a user hit it via openclaw on Telegram — there was no automated detection. Four layers of observability would have reduced time-to-detection:

1. **Uptime / synthetic monitoring (Gatus)** — External HTTP checks against `bifrost.dimensiondoor.xyz/v1/models`, `clawd.dimensiondoor.xyz`, etc. every 30-60s, alerting to ntfy on non-200 responses. This is the highest-value, lowest-effort improvement and would have caught the 503 within a minute of the upgrade.

2. **Flux alerts to ntfy** — The notification-controller is already running in `flux-system`. Configuring it to push reconciliation failures (HelmRelease, Kustomization, GitRepository) to ntfy would have flagged both the Codeberg connectivity issue and any future reconciliation problems.

3. **HelmRelease health checks** — Flux supports `spec.healthChecks` on HelmReleases to verify Deployments have ready replicas before marking a release as successful. This would have made the bifrost HelmRelease show as *failed* instead of "upgrade succeeded," making the problem immediately visible in `flux get helmrelease`.

4. **kube-state-metrics + Prometheus alerting** — Metrics like `kube_deployment_status_replicas_available == 0` catch the structural problem (service exists, pods don't) that Helm and Flux both missed. More involved to set up but covers a broad class of cluster health issues (crashlooping pods, unbound PVCs, pending pods stuck on scheduling).

## Lessons

- **Pin Helm chart versions exactly in GitOps.** `>=1.0.0` is not a version constraint, it is an auto-upgrade policy. Major version bumps can change template logic, value schemas, and resource types. Pin to exact versions and bump explicitly.
- **"Upgrade succeeded" means nothing about workload health.** Helm validates syntax and API acceptance, not that pods exist or are running. After any chart upgrade, verify that the expected workload objects are present.
- **Declare everything that matters in version control.** Virtual keys, runtime config, plugin settings — if it is not in a HelmRelease values block or a ConfigMap, it will eventually be lost. Dashboards are for viewing, not for storing configuration of record.
- **Setup scripts must be idempotent.** A script that runs on every service restart must merge state, not replace it. Full replacement is only safe on first run.
- **When Flux cannot reach the source, you can still patch resources directly.** `kubectl patch` on HelmRelease works as an escape hatch but should be followed by a commit to the source repo once connectivity returns, to avoid drift.
