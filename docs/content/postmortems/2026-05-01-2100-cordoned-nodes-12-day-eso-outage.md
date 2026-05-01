---
date: 2026-04-19
title: Cordoned nodes caused 12-day silent ESO outage blocking all Flux deployments
severity: major
duration: 12 days (Apr 19 – May 1)
systems: [kubernetes, external-secrets, longhorn, flux, boromir, samwise, theoden, bifrost]
tags: [kubernetes, k3s, longhorn, flux, external-secrets, storage, disk-pressure, cordon]
commit: https://codeberg.org/ananjiani/infra/commit/bc13c87
---

## Summary

On April 19, boromir and samwise were drained for a shutdown and never uncordoned. The `k3s-auto-uncordon` service failed because k3s couldn't start fast enough (vault-agent chicken-and-egg). Simultaneously, theoden developed disk pressure from 4.1G of journal logs. With boromir/samwise cordoned and theoden tainted, External Secrets Operator had nowhere to schedule — its pods had an anti-affinity rule excluding rivendell. All 19 ExternalSecrets went stale, all Flux kustomizations downstream of `infrastructure` failed, and no k8s changes could deploy for 12 days. The outage was discovered incidentally while deploying LLM key consolidation.

## Timeline

All times CDT (UTC-5).

- **Apr 19 ~19:39** — boromir and samwise rebooted. `k3s-auto-uncordon` started on boromir.
- **Apr 19 ~19:44** — `k3s-auto-uncordon` gave up: "Warning: boromir did not become Ready within 5 minutes, skipping uncordon". Exited status 0 (success).
- **Apr 19 ~20:44** — k3s finally started on boromir (vault-agent needed multiple retries to render `/run/secrets/k3s_token`). By this point the uncordon service had already exited permanently.
- **Apr 19 20:45:12** — k3s drain hook ran during the earlier shutdown, leaving the `node.kubernetes.io/unschedulable` taint in place.
- **Apr 28** — theoden hit disk pressure (92% /, 4.1G journal + 85G nix store). Kubelet added `node.kubernetes.io/disk-pressure` NoSchedule taint.
- **~Apr 24-28** (estimated) — ESO pods on theoden went `ContainerStatusUnknown` as old replicas died. New replicas couldn't schedule anywhere.
- **May 1 15:24** — LLM key consolidation committed and pushed. Discovery phase began.
- **May 1 15:30** — Flux reconciliation attempted, failed: `infrastructure` kustomization blocked by `external-secrets` HelmRelease status `Failed`.
- **May 1 15:40** — Investigated: all ESO pods `Pending`/`ContainerStatusUnknown`. Identified the scheduling deadlock.
- **May 1 15:45** — Uncordoned boromir and samwise. ESO pods began scheduling.
- **May 1 15:50** — ESO HelmRelease reconciled. All 19 ExternalSecrets synced within 2 minutes.
- **May 1 16:00** — theoden disk pressure: vacuumed 3.5G of journal logs (4.1G → 600M). Restarted k3s to clear the kubelet's cached disk-pressure state.
- **May 1 16:10** — Longhorn CSI driver on theoden didn't register after k3s restart (`CSINode.spec.drivers: null`). Deleted and recreated the CSI plugin pod to force re-registration.
- **May 1 16:20** — Bifrost and Open-WebUI PVCs stuck in Multi-Attach / `detaching` state. Had to force-delete stale pods on theoden so Longhorn could detach volumes.
- **May 1 16:35** — All Flux kustomizations reconciled at commit `1a254835` (bc13c87). All services running.

## What Happened

The sequence started with a shutdown on April 19 (likely UPS-triggered or manual maintenance). The `k3s-graceful-drain` service drained boromir and samwise — this is by design. The `k3s-auto-uncordon` service is supposed to reverse this on boot: wait for the node to become `Ready`, then uncordon.

But k3s on boromir couldn't start because it was waiting for `/run/secrets/k3s_token`, which vault-agent renders. Vault-agent was also restarting (its own dependency cycle). After 5 minutes, `k3s-auto-uncordon` gave up and exited with status 0 — treating the timeout as a non-error. When k3s finally started ~5 minutes later, the uncordon service had already exited and wouldn't run again until next boot.

Meanwhile on theoden, journald had been accumulating logs for 60 days without vacuuming. The root filesystem hit 92%, triggering kubelet disk-pressure taint on April 28. This removed theoden as a scheduling target.

External Secrets Operator has an anti-affinity rule: `kubernetes.io/hostname NotIn rivendell`. So with boromir cordoned, samwise cordoned, theoden tainted, and rivendell excluded by anti-affinity — ESO had zero schedulable nodes. All its pods died or went unknown. Every ExternalSecret in the cluster went stale. Every Flux kustomization downstream of `infrastructure` failed health checks.

Nobody noticed for 12 days because no alerts fire when ExternalSecrets go stale (they don't have a "stale" condition — they just stop updating).

## Contributing Factors

- **`k3s-auto-uncordon` exits on timeout** — The service waits 5 minutes then exits with status 0, making systemd consider it "successful". It never retries. If k3s takes longer than 5 minutes to become Ready (which happens regularly due to vault-agent chicken-and-egg), the node stays cordoned permanently.
- **vault-agent bootstrap latency on boromir** — k3s can't start without `/run/secrets/k3s_token`. Vault-agent needs its own AppRole secret from SOPS, which sops-nix deposits. The chain (boot → sops-nix → vault-agent → k3s) can take >5 minutes on busy nodes.
- **No disk journal vacuuming on theoden** — The server had no journald size limit configured. 60 days of logs accumulated to 4.1G, contributing to disk pressure on a 197G root.
- **ESO anti-affinity excludes rivendell** — The only worker node without a taint was explicitly excluded from ESO scheduling. This was likely intentional (rivendell has the r8169 NIC issues), but it means ESO has no fallback when control-plane nodes are unavailable.
- **No monitoring for ExternalSecret staleness** — Flux health checks catch HelmReleases, but not the ExternalSecret → Secret dependency. Secrets just freeze at their last-synced values.
- **No alerting for cordoned nodes** — Nodes being `SchedulingDisabled` for 12 days triggered no notifications.

## What I Was Wrong About

- **I assumed the auto-uncordon was reliable.** It was written as a safety net (commit `010debf`, Feb 21), but the 5-minute timeout makes it fragile exactly when it's needed most — after an unclean shutdown where services are slow to come up.
- **I assumed I'd notice if nodes were cordoned.** In practice, `kubectl get nodes` shows `Ready,SchedulingDisabled` which looks fine at a glance. Nothing red, no alerts.
- **I assumed Flux would surface the problem.** Flux did show `infrastructure` as `False`, but I only checked because I was deploying something. There was no proactive notification.

## What Helped

- **Flux dependency ordering** — The `infrastructure → external-secrets-config → apps` chain meant that when ESO came back, everything downstream reconciled automatically within minutes. No manual rollout needed.
- **ExternalSecrets are declarative** — Once ESO pods were running, all 19 secrets synced from Bao in under 2 minutes. No manual secret creation needed.
- **The consolidation work surfacing the problem** — If I hadn't been deploying the LLM key changes, I might not have noticed for even longer. The deployment was the canary.

## What Could Have Been Worse

- **Secrets containing certificates could have expired** during the 12 days. If cert-manager's Cloudflare API token went stale, TLS certs would fail to renew, causing browser errors on all `*.dimensiondoor.xyz` endpoints.
- **Bifrost going down during the outage** could have been catastrophic if services still depended on it (they did). The LLM consolidation to bypass Bifrost was done while Bifrost was already in a failed state.
- **rivendell going down** would have meant zero schedulable nodes for *any* workload, not just ESO. It was the single point of failure for the entire cluster during this window.

## Is This a Pattern?

- [x] Pattern: The approach to node lifecycle management needs to change.

This is the second time cordoned nodes caused a silent outage (see `2026-03-07-1900-flannel-subnet-env-power-outage.md` for the first). The drain/uncordon mechanism is too fragile:

1. The drain hook works reliably (it's synchronous during shutdown).
2. The uncordon hook fails silently (timeout → exit 0 → never retries).

The asymmetry is the problem. Drain is guaranteed; uncordon is best-effort.

Additionally, the lack of alerting for basic cluster health (cordoned nodes, stale secrets, disk pressure) means problems accumulate invisibly.

## Action Items

- [ ] Make `k3s-auto-uncordon` persistent: use a `Restart=on-failure` or `Restart=always` systemd service with a longer timeout (30 min), or convert to a timer that runs every 5 minutes until the node is uncordoned
- [ ] Add journald size limits to server configs: `services.journald.extraConfig = "SystemMaxUse=500M"` in the base server profile
- [ ] Add Prometheus/alertmanager rules for: nodes cordoned >1h, ExternalSecret last sync >2h, node disk pressure
- [ ] Remove ESO anti-affinity against rivendell (or add a comment explaining why it's worth the risk), so ESO has at least one fallback node
- [ ] Add `kubectl get nodes` status to the Homepage dashboard or a periodic health check script

## Lessons

- A safety net that exits successfully on failure is worse than no safety net — it gives false confidence.
- The vault-agent → k3s bootstrap chain on control-plane nodes regularly takes >5 minutes. Any automation that depends on k3s being Ready quickly needs to account for this.
- Disk pressure is insidious because kubelet caches the condition and doesn't re-check often. Vacuuming journals fixed the disk, but the taint persisted until k3s was restarted.
- `kubectl get nodes` showing `Ready` is not sufficient — `SchedulingDisabled` is easy to miss.
- Longhorn CSI driver registration on a node is not automatic after a k3s restart. The CSI plugin pod must be deleted and recreated to trigger re-registration with the kubelet.
