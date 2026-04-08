---
date: 2026-04-02
title: Rohan IO pressure causes theoden VM hang and Zot registry outage
severity: moderate
duration: ~30m
systems: [rohan, theoden, zot, k3s, forgejo-runner]
tags: [proxmox, memory, io-pressure, kubernetes]
commit:
---

## Summary

The theoden VM (on Proxmox host rohan) became unresponsive due to extreme IO pressure on the hypervisor. This caused the kubelet to stop posting heartbeats, Zot registry readiness probes to fail, and Forgejo Actions CI jobs to fail with "connection refused" when pulling container images. Resolved by reducing theoden's RAM allocation from 22GB to 20GB and rebooting the VM.

## Timeline

All times CST.

- **~11:00** - Forgejo Actions runner reports `connection refused` pulling image from `zot.zot.svc.cluster.local:5000`
- **~11:10** - Investigation begins. Zot pod is `0/1 Running` — readiness probes failing with "context deadline exceeded"
- **~11:12** - theoden node is `NotReady` — "Kubelet stopped posting node status" since ~11:27 (node time)
- **~11:15** - SSH to theoden hangs at banner exchange. TCP handshake succeeds but sshd can't complete negotiation
- **~11:20** - Ping to rohan (192.168.1.24) succeeds. SSH to rohan succeeds
- **~11:25** - QEMU guest agent commands to theoden (VM 104) timeout
- **~11:30** - Rohan diagnostics reveal: IO pressure full 64.95%, IO pressure some 82.95%, load average 20.13 (4 CPUs), only 366MB free RAM on host out of 23GB. theoden allocated 22GB
- **~11:35** - Reduced theoden RAM from 22528MB to 20480MB via `qm set 104 --memory 20480`. Rebooted VM via `qm reboot 104`, then `qm stop 104 --skiplock` when the reboot hung
- **~11:40** - theoden boots with 20GB RAM, 13GB free. k3s activating
- **~11:42** - theoden reaches `Ready` state. Zot pod starts and passes readiness probes. Service endpoints repopulated

## What Happened

A CI job on Forgejo triggered a workflow that needed to pull a container image from the in-cluster Zot registry mirror. The pull failed with "connection refused" on the Zot service's ClusterIP.

Investigation showed the Zot pod was running but not ready — its HTTP readiness probe to `/v2/` was timing out. This traced back to theoden being `NotReady`, with all node conditions showing `Unknown` ("Kubelet stopped posting node status").

Attempting to SSH into theoden revealed the VM was effectively hung — TCP connections were accepted but sshd couldn't complete the banner exchange, indicating extreme system load. The QEMU guest agent also timed out.

Accessing the Proxmox host (rohan) directly revealed the root cause: with theoden allocated 22GB on a 23GB host, rohan had less than 400MB free for itself. Linux PSI metrics showed IO pressure at 65-83%, meaning most processes were stalled waiting on IO — almost certainly swap thrashing. The load average of 20 on a 4-core machine confirmed massive IO wait queuing.

The fix was to reduce theoden's RAM to 20GB (giving rohan ~4GB headroom) and force-reboot the VM. The initial `qm reboot` hung because ACPI shutdown requires guest cooperation, so a `qm stop --skiplock` was needed to force it. After restart, theoden came back healthy with 13GB free, k3s rejoined the cluster, and Zot resumed serving requests.

## Contributing Factors

- **Theoden allocated 22GB on a 23GB host**: The original comment said "leaving ~2GB for Proxmox host" but in practice QEMU overhead, page cache needs, and kernel buffers meant ~1GB was actually usable — not enough under any sustained load
- **No memory ballooning**: `balloon: 0` means the VM always claims its full allocation, even when idle. The guest can't return unused memory to the host
- **Zot pinned to theoden via nodeSelector**: When theoden goes down, Zot has no failover path. The pod goes Pending until the specific node recovers
- **No alerting on host-level resource pressure**: PSI metrics were available but not monitored, so the problem wasn't caught until it caused a user-visible failure

## What I Was Wrong About

- **"~2GB for the host is enough"**: For a hypervisor running a single VM with multiple passthrough disks and NFS serving duties, 2GB is not enough headroom. The host needs memory for QEMU process overhead, VirtIO buffers, disk page cache (especially important for the passthrough disks theoden uses for NFS), and kernel data structures. 4GB is a more realistic minimum.
- **Initial suspicion of comfyui**: The podman veth churn in rohan's dmesg looked like a crashlooping container, but it turned out to be from inside the theoden VM (QEMU reports guest kernel messages). Rohan had no podman containers at all.

## What Helped

- **Proxmox QEMU guest agent and `qm` CLI**: Even though the guest agent timed out, `qm status --verbose` provided PSI pressure metrics from inside the VM, which immediately pointed to IO pressure as the cause
- **VM status still showed "running"**: Despite the hang, the VM process was alive enough that `qm set` could change its config (applied on next boot) without needing to modify config files directly
- **`qm stop --skiplock`**: When the reboot hung and locked the config file, this flag allowed forcing the stop

## What Could Have Been Worse

- **etcd data corruption**: theoden is a control-plane + etcd node. An unclean shutdown under extreme IO pressure could have corrupted etcd, requiring cluster recovery (which has been painful before — see etcd recovery notes in memory)
- **NFS data loss**: theoden serves NFS storage (including for Zot). If the IO stall had caused filesystem corruption on the passthrough disks, data loss would have been much harder to recover from
- **Longer outage if rohan was also unreachable**: If rohan's SSH had been affected (it wasn't, since it had just enough memory), the only option would have been physical access or IPMI (which rohan doesn't have)

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This is the same class of issue as previous disk/memory pressure cascades (see memory notes on Longhorn eviction cascades, DiskPressure on nodes). The homelab has a recurring pattern of running VMs very close to host resource limits, then experiencing cascading failures when any component demands a burst of resources.

Rohan specifically is the weakest host (i5-3570K, 24GB RAM, oldest hardware), yet runs theoden which handles k3s control plane + NFS storage + Longhorn — all IO-heavy workloads.

## Action Items

- [x] Reduce theoden RAM from 22GB to 20GB (done: Terraform config + live `qm set`)
- [x] Enable memory ballooning on theoden so unused guest RAM is returned to rohan (done: Terraform `floating = 20480` + live `qm set`)
- [x] Add PSI-based alerting for Proxmox hosts — IO pressure >10% warning, >30% critical, memory pressure >5% warning (done: `proxmox-pressure-alerts` in kube-prometheus-stack)
- [x] Remove Zot nodeSelector to allow failover from theoden (done — see rationale below)

### Zot nodeSelector removal rationale

The original logic for pinning Zot to theoden was: since Zot's NFS storage lives on theoden (`192.168.1.27:/srv/nfs/zot`), it needs theoden to be up anyway, so pinning avoids an unnecessary network hop for NFS.

That reasoning is sound for the happy path, but it conflates two failure modes:

1. **theoden OS is running but k3s/kubelet is unhealthy** — NFS still serves, but the nodeSelector prevents Zot from rescheduling to a healthy node. This is exactly what happened in this incident: theoden was alive enough to serve network traffic but its kubelet couldn't post heartbeats.
2. **theoden is fully down** — NFS is unavailable regardless of where Zot is scheduled, so the nodeSelector doesn't matter.

Removing the nodeSelector helps with case 1 (which is the more common failure mode under resource pressure) at zero cost for case 2. The NFS network hop from another node adds negligible latency for a registry mirror doing on-demand pulls from upstream.

If the NFS locality ever matters for performance, a `preferredDuringSchedulingIgnoredDuringExecution` node affinity can express "prefer theoden but don't require it."

## Lessons

- **Hypervisor headroom is not optional**: A VM consuming 95%+ of host RAM will eventually cause IO pressure from swap thrashing. 80-85% is a safer ceiling for hosts without ECC RAM and enterprise storage.
- **PSI metrics are the fastest diagnostic for "system is hung"**: `pressureiofull` > 50% immediately explains why everything is slow/unresponsive, without needing to get a shell on the affected system.
- **"Connection refused" on a ClusterIP means zero endpoints**: When debugging k8s service connectivity, check endpoints first — it's almost always a pod health issue, not a network issue.
