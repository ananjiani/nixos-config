---
date: 2026-01-25
title: K8s node failure caused cascading service outages due to Longhorn failover misconfiguration
severity: major
duration: ~41h
systems: [k3s, longhorn, authentik, forgejo, open-webui, chromadb]
tags: [kubernetes, storage, high-availability, statefulset]
commit: https://codeberg.org/ananjiani/infra/commit/72f0f55
---

## Summary

When the theoden node became unreachable, StatefulSet pods (databases, storage) failed to failover to healthy nodes, causing a cascade of dependent service failures. The outage lasted approximately 41 hours until manual intervention. Root cause was Longhorn's failover policy only covering Deployments, not StatefulSets.

## Timeline

All times in CST (approximate, reconstructed from pod ages).

- **~Jan 24 01:00** - Shut down rohan (Proxmox host) for planned maintenance (adding drives)
- **~Jan 24 01:00** - Theoden VM (hosted on rohan) became unreachable (NotReady)
- **~Jan 24 01:05** - Kubernetes marked StatefulSet pods for termination, but they stuck in Terminating state
- **~Jan 24 01:05** - Dependent services (authentik-worker, forgejo, open-webui) entered CrashLoopBackOff
- **~Jan 24 ??:??** - Rohan powered back on but failed to boot (boot order changed to new drives)
- **Jan 25 12:30** - Investigation began after user reported cluster problems
- **Jan 25 12:35** - Identified theoden NotReady, multiple pods stuck Terminating
- **Jan 25 12:40** - Identified Longhorn's nodeDownPodDeletionPolicy as the issue
- **Jan 25 12:45** - Applied fix: changed policy to delete-statefulset-pod
- **Jan 25 12:50** - Fixed rohan boot order, theoden came back online, Terminating pods cleared
- **Jan 25 12:55** - Force-restarted CrashLoopBackOff pods, services recovered
- **Jan 25 13:00** - All services confirmed healthy

## What Happened

The k3s cluster has three control-plane nodes: boromir, samwise, and theoden. Theoden runs as a VM on rohan, a Proxmox host. During planned maintenance to add drives to rohan, theoden became unavailable. Rohan didn't come back up cleanly because the boot order had changed to try booting from one of the new drives.

This was a reasonable maintenance operation - the expectation was that the cluster would continue operating on two nodes while theoden was down. Kubernetes correctly identified theoden as NotReady and attempted to reschedule pods.

However, StatefulSet pods with Longhorn persistent volumes could not be rescheduled. Longhorn's `nodeDownPodDeletionPolicy` was set to `delete-deployment-pod`, which only handles Deployment pods. StatefulSet pods (authentik-postgresql, chromadb, minio, postgres) remained stuck in Terminating state because:

1. The kubelet on theoden couldn't confirm deletion (node unreachable)
2. Longhorn wouldn't force-detach the volumes without the policy covering StatefulSets
3. New pods couldn't start because volumes were still "attached" to the dead node

This created a cascade:
- authentik-postgresql stuck → authentik-worker couldn't connect to DB → CrashLoopBackOff
- chromadb stuck → open-webui couldn't connect to vector DB → CrashLoopBackOff
- authentik down → forgejo couldn't complete OAuth setup → Init:CrashLoopBackOff

The cluster appeared to have "high availability" with 3 nodes and 3 replicas per volume, but the failover automation was incomplete.

## Contributing Factors

- **Longhorn policy misconfiguration**: `nodeDownPodDeletionPolicy: delete-deployment-pod` only covered Deployments, not StatefulSets
- **Single-replica StatefulSets**: Each database was a single instance, not a replicated cluster
- **No monitoring/alerting**: The 41-hour outage went unnoticed until manual check
- **Mental model mismatch**: Assumed "3 replicas" for Longhorn volumes meant automatic failover for all workloads

## What I Was Wrong About

- **"I can take down one node for maintenance and the cluster will be fine"** - The whole point of a 3-node cluster is to survive single-node failure. This assumption was correct in theory but the implementation was incomplete.
- **"Longhorn handles failover automatically"** - Longhorn replicates data, but pod deletion on node failure requires explicit policy configuration
- **"3 nodes + 3 replicas = HA"** - Data was replicated, but the orchestration to actually failover was missing for StatefulSets
- **"Kubernetes will reschedule pods"** - Kubernetes tries, but storage systems can block this if they think data might be corrupted

## What Helped

- **Longhorn volume replicas**: Data was safe on healthy nodes, just inaccessible. No data loss occurred.
- **Theoden eventually recovered**: The node came back online during investigation, which cleared Terminating pods automatically
- **Clear error cascade**: CrashLoopBackOff logs clearly showed "can't connect to X", making dependency chain obvious

## What Could Have Been Worse

- **Data loss**: If Longhorn hadn't replicated data, or if the volume had only 1 replica on theoden, data would have been lost
- **Longer outage**: Without the coincidental theoden recovery, manual force-deletion would have been needed for every stuck pod
- **Split-brain**: If theoden had been partially reachable (network partition), Longhorn's fencing might have caused data corruption

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This reveals a gap in the homelab's HA strategy. The assumption was "replicated storage = automatic failover" but that's incomplete. StatefulSet failover requires:
1. Storage system cooperation (Longhorn policy)
2. Kubernetes node eviction timeouts
3. Proper fencing/STONITH

Additionally, single-instance databases are inherently not HA regardless of storage replication.

## Action Items

- [x] Change Longhorn nodeDownPodDeletionPolicy to delete-statefulset-pod (completed: 72f0f55)
- [ ] Add monitoring/alerting for node NotReady status (Prometheus alert)
- [ ] Add monitoring/alerting for pods stuck in Terminating > 10 minutes
- [ ] Document the expected failover behavior and test it intentionally
- [ ] Consider replicated database setups (PostgreSQL HA) for critical services
- [ ] Review Kubernetes node eviction timeouts (--pod-eviction-timeout)

## Lessons

- **Storage replication ≠ automatic failover**: Longhorn replicates data across nodes, but orchestrating pod failover is a separate concern requiring explicit configuration.
- **Test your HA assumptions**: "It should failover" is not the same as "I've tested failover and it works."
- **StatefulSets are special**: They have different lifecycle semantics than Deployments. Configuration that works for one may not work for the other.
- **Check Longhorn settings specifically**: `nodeDownPodDeletionPolicy` is critical for automatic recovery. The default (`do-nothing`) is very conservative.
- **Next time I see pods stuck Terminating after node failure**: First check Longhorn's deletion policy, then consider force-deleting pods with `--force --grace-period=0`.
