---
date: 2026-03-07
title: Flannel subnet.env missing after power outage — cluster-wide pod scheduling failure
severity: major
duration: 2h 30m
systems: [k3s, flannel, longhorn, deploy-rs]
tags: [kubernetes, networking, flannel, power-outage, nix]
commit:
---

## Summary

After a power outage, all four k3s nodes came back up but flannel's `/run/flannel/subnet.env` was missing on three of four nodes (boromir, samwise, theoden). This prevented all pod networking — no pods could start on those nodes. Rivendell (agent node) was the only node that recovered because it had a valid persistent backup. The cluster was effectively down for ~2.5 hours until the flannel-restore service was enhanced with a declarative `podCidr` fallback and manually deployed to all nodes.

## Timeline

All times CST.

- **~16:58** - Power restored. All four nodes boot, k3s starts on each.
- **~16:59** - `k3s-flannel-restore` runs on all nodes. Rivendell restores from backup. Boromir, samwise, theoden log "No flannel backup found" — `/var/lib/rancher/k3s/flannel-subnet.env` does not exist.
- **~16:59** - k3s starts on all nodes. Embedded flannel on server nodes silently fails to write `/run/flannel/subnet.env`. Pods begin failing with `loadFlannelSubnetEnv failed: open /run/flannel/subnet.env: no such file or directory`.
- **~17:01** - `k3s-flannel-mtu` runs, finds no cni0 bridge, exits cleanly.
- **~17:01 – 18:10** - Cluster sits with all nodes `Ready` but zero pod scheduling on 3/4 nodes. Longhorn admission webhook unreachable, blocking k3s node operations.
- **~18:10** - Investigation begins. Identified `/run/flannel/subnet.env` missing on all server nodes. Confirmed rivendell working because its backup existed.
- **~18:14** - Attempted k3s restart on boromir — flannel still did not write subnet.env. Startup logs showed no "Starting flannel" message at all.
- **~18:30** - Discovered mismatch context: December 30 logs show flannel initializing with `vxlan` backend, but current k3s config specifies `host-gw`. However, node annotations were already correct (`host-gw`). Flannel simply never initialized on this boot.
- **~18:45** - Decision to add declarative `podCidr` option to k3s NixOS module as a fallback for flannel-restore.
- **~19:05** - Built and deployed new config to boromir via deploy-rs. Deploy-rs rolled back due to tailscaled-autoconnect timeout (Headscale runs in k3s — chicken-and-egg).
- **~19:05** - However, the first activation did trigger flannel-restore, which generated subnet.env from the new `podCidr` fallback. File survived the rollback (lives in `/run` tmpfs, not affected by NixOS profile switch).
- **~19:09** - Manually activated config on boromir using `nix-env --set && switch-to-configuration switch`.
- **~19:11** - Built and copied closures to samwise and theoden in parallel. Manual activation on both.
- **~19:13** - All three server nodes activated. Restarted k3s on all three.
- **~19:14** - subnet.env present on all nodes. cni0 bridge created. CoreDNS, metrics-server running.
- **~19:15** - Longhorn instance managers, CSI plugins, and engine images running on all 4 nodes. Deleted stale `Unknown` pods.
- **~19:17** - Volumes still detached — stale VolumeAttachments with `ATTACHED=false` blocking. Restarted all Longhorn CSI sidecars (attacher, provisioner, resizer, snapshotter).
- **~19:18** - All 15 volumes attached. Pods begin scheduling.
- **~19:25** - All pods Running. 6/15 volumes healthy, 9 degraded (replica rebuilds in progress).
- **~19:30** - Deleted stopped replicas on theoden to trigger fresh rebuilds.
- **~19:45** - 10/15 volumes healthy. Second batch of stopped replicas deleted.
- **~20:00** - All pods running. Remaining volumes rebuilding 3rd replicas in background.

## What Happened

A power outage took down all four k3s nodes simultaneously. On reboot, `/run` (tmpfs) was wiped clean, including `/run/flannel/subnet.env` which the flannel CNI plugin needs to assign pod IPs.

The `k3s-flannel-restore` service (added after the January 31 incident) ran before k3s on each node and attempted to restore subnet.env from a persistent backup at `/var/lib/rancher/k3s/flannel-subnet.env`. On rivendell, this backup existed and the restore worked. On the three server nodes, no backup existed — the backup had never been created because k3s's embedded flannel had never successfully written subnet.env on these nodes with the `host-gw` backend.

The backup/restore mechanism was designed for the case where flannel writes subnet.env once, the backup service persists it, and subsequent reboots restore from backup. But there was a gap: if flannel never writes the file in the first place (e.g., first boot after switching from vxlan to host-gw, or if the embedded flannel silently fails), the backup never gets created, and the restore has nothing to restore.

k3s's embedded flannel on the server nodes simply did not initialize on this boot. The startup logs show etcd, containerd, and kube-proxy starting, but no "Starting flannel" message. The exact reason remains unclear — possibly a race condition in k3s startup, or a silent failure related to the backend configuration. Restarting k3s alone did not fix it; the subnet.env file had to be seeded before k3s started.

The fix was to add a `podCidr` option to the k3s NixOS module. When the flannel-restore service finds no backup, it now generates subnet.env from the declared podCidr — effectively making the flannel CNI bootstrap declarative rather than relying on k3s's embedded flannel to write it.

Deployment was complicated by the tailscaled-autoconnect chicken-and-egg: Tailscale needs Headscale, which runs in k3s, but k3s can't start pods because flannel is broken. deploy-rs rolls back on any unit failure. The workaround was `nix-env --set && switch-to-configuration switch` to bypass deploy-rs activation checks.

After flannel was fixed, Longhorn recovery required additional intervention: stale VolumeAttachments prevented re-attachment, and CSI sidecars had cached stale state from the outage. Deleting the CSI sidecar pods and stopped replicas unblocked the recovery.

## Contributing Factors

- **No persistent flannel backup on server nodes**: The backup/restore mechanism assumed flannel would write subnet.env at least once. On nodes that were deployed with `host-gw` but where embedded flannel never successfully initialized, the backup was never created.
- **k3s embedded flannel silent failure**: On this boot, flannel within k3s simply did not start on any server node. No error message, no "Starting flannel" log line — it silently failed to initialize. The exact trigger is unknown.
- **Simultaneous power loss to all nodes**: A rolling restart would have allowed flannel to recover from peers. All-at-once meant no node had a working flannel to bootstrap from.
- **deploy-rs rollback on tailscaled-autoconnect failure**: The chicken-and-egg with Headscale running in k3s means deploy-rs can't complete activation when the cluster is down, requiring manual `nix-env` workaround.
- **Longhorn CSI sidecars caching stale state**: After networking recovery, the CSI attacher, provisioner, resizer, and snapshotter pods retained stale IPs/routes from the outage period, preventing volume re-attachment until restarted.

## What I Was Wrong About

- **"The backup/restore mechanism handles reboots"**: It does — but only if the backup exists. The gap was the first-boot case (or any case where flannel never wrote subnet.env). The backup mechanism was designed for the common case but not the cold-start case.
- **"Restarting k3s will fix flannel"**: k3s restarts did not cause embedded flannel to reinitialize. The file had to be pre-seeded.
- **"Node annotations being correct (host-gw) means flannel is configured right"**: The annotations were correct but flannel still didn't start. Annotations are metadata — they don't cause flannel to initialize.

## What Helped

- **Rivendell's persistent backup**: Having one working node (rivendell) as a reference made it immediately clear what was wrong — comparing its working state to the broken servers.
- **Known podCIDR assignments in etcd**: The podCIDRs were stable (assigned at node creation, stored in etcd), so we could safely declare them in NixOS config without risk of mismatch.
- **The `nix copy && nix-env --set` deploy workaround**: Documented in MEMORY.md from previous incidents, this bypass was already known and ready to use.
- **Flannel subnet.env format is simple**: Just 4 key-value lines. Easy to generate declaratively.

## What Could Have Been Worse

- **etcd data loss**: The power outage could have corrupted etcd. In this case, etcd recovered cleanly on all three server nodes with recent snapshots intact.
- **Longhorn volume corruption**: Volumes had been running without I/O for ~2 hours during the outage. All 15 volumes attached without data corruption — Longhorn's write journaling held up.
- **podCIDR reassignment**: If etcd had needed recovery, nodes could have gotten different podCIDRs, making the hardcoded `podCidr` option wrong. This didn't happen.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This is the **third flannel-related incident** (after 2026-01-31 subnet.env reboot failure and 2026-03-02 VIP route corruption). The pattern is that k3s's embedded flannel has multiple silent failure modes, and `/run/flannel/subnet.env` is a critical single point of failure that lives on tmpfs.

The approach of relying on k3s's embedded flannel to self-heal is fundamentally fragile. The declarative `podCidr` fallback makes the system self-healing regardless of what k3s's embedded flannel does.

## Action Items

- [x] Add `podCidr` option to k3s NixOS module with declarative fallback in flannel-restore service
- [x] Set `podCidr` on all 4 nodes (boromir: 10.42.1.0/24, samwise: 10.42.2.0/24, theoden: 10.42.3.0/24, rivendell: 10.42.0.0/24)
- [x] Deploy to all nodes and verify subnet.env generation
- [ ] Commit the `podCidr` changes to the repository
- [ ] Consider adding a postmortem recovery runbook for "cluster down after power outage" scenario
- [ ] Investigate why k3s embedded flannel silently fails to initialize on server nodes with host-gw backend

## Lessons

- **Backup/restore is not enough if the backup was never created.** Any backup-based resilience mechanism needs a fallback for the cold-start case. The declarative `podCidr` is that fallback.
- **After any networking change (flannel restart, route fix), always restart Longhorn CSI sidecars.** They cache stale IPs/routes and won't self-heal.
- **Stopped Longhorn replicas don't auto-rebuild.** After an extended outage, manually delete stopped replicas to trigger fresh rebuilds on healthy nodes.
- **When deploy-rs can't complete (Tailscale/Headscale chicken-and-egg), use `nix-env --set && switch-to-configuration switch`.** This is a known pattern — keep it in MEMORY.md.
