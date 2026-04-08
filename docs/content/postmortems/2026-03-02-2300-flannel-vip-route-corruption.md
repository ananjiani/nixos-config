---
date: 2026-03-02
title: Flannel route corruption from keepalived VIPs breaks pod networking and IPVS
severity: major
duration: ~8h (across two sessions)
systems: [k3s, flannel, keepalived, kube-proxy, ipvs, longhorn]
tags: [kubernetes, networking, flannel, keepalived, ipvs, longhorn, storage]
commit: https://codeberg.org/ananjiani/infra/commit/dca6594
---

## Summary

After enabling IPVS kube-proxy mode, all pod-to-ClusterIP traffic broke (connections stuck in SYN_RECV). The immediate cause was stale flannel routes pointing each node's own pod CIDR to the wrong host. The underlying cause was keepalived VIPs on the same interface as flannel, causing flannel to auto-detect VIPs as the node's public IP and generate corrupted routes cluster-wide. A secondary issue — the NixOS firewall silently dropping IPVS traffic on the INPUT chain — compounded the problem. Recovery also required unsticking 7 Longhorn volumes that became faulted during the extended networking outage.

## Timeline

All times CST.

- **~15:00** - Deployed IPVS kube-proxy mode (`--kube-proxy-arg=proxy-mode=ipvs`) to all 4 k3s nodes via deploy-rs.
- **~15:30** - Noticed all pod-to-ClusterIP traffic broken. IPVS connection table showed all connections stuck in SYN_RECV.
- **~16:00** - Investigated iptables chains (FORWARD, KUBE-FORWARD, FLANNEL-FWD, KUBE-POSTROUTING). All looked correct.
- **~16:30** - Used `/proc/net/nf_conntrack` (conntrack tool not installed) to find connection entries. SYN packets entering but no SYN-ACK returning.
- **~17:00** - tcpdump on cni0 showed SYN packets from pods but NO SYN-ACK. tcpdump on ens18 showed no DNAT'd pod traffic leaving. Checked routing: `ip route get 10.42.1.17` returned `via 192.168.1.26 dev ens18` — boromir's own pod CIDR was routing to samwise.
- **~17:15** - Discovered duplicate routes on every node: stale `10.42.x.0/24 via <wrong-host>` alongside correct `10.42.x.0/24 dev cni0`. The `via` route took precedence, breaking local pod traffic.
- **~17:20** - Manually deleted stale routes on all 4 nodes. IPVS connections immediately went from SYN_RECV to ESTABLISHED. Pods working.
- **~17:30** - Investigated permanent fix. Found flannel node annotations showed VIP addresses (192.168.1.53, .54) instead of real node IPs. Keepalived VIPs on ens18 were being picked up by flannel.
- **~18:00** - Tried `--flannel-iface=ens18`. Flannel still picked up VIPs because it iterates all IPs on the specified interface.
- **~18:30** - Tried manually setting `flannel.alpha.coreos.com/public-ip-overwrite` annotation. k3s embedded flannel ignored it.
- **~19:00** - Discovered `--flannel-external-ip` + `--node-external-ip=<nodeIp>` triggers the k3s Cloud Controller Manager to set the `public-ip-overwrite` annotation in a way flannel actually respects. Deployed to all nodes.
- **~19:30** - Verified all flannel annotations correct, all routes clean, IPVS working (13 ESTABLISHED, 0 SYN_RECV).
- **~19:45** - Found NixOS firewall was silently dropping pod→ClusterIP traffic on INPUT chain. Added `iptables -I nixos-fw 1 -i cni0 -s 10.42.0.0/16 -d 10.43.0.0/16 -j nixos-fw-accept`. Committed all changes.
- **~20:00** - Turned attention to 9 non-running pods. 7 Longhorn volumes stuck in `detaching`/`faulted`, 10 stale VolumeAttachments.
- **~23:00** (session 2) - Resumed Longhorn recovery. Restarted theoden's stale instance-manager (24h old, wrong IP from pre-fix era). 4 volumes unblocked.
- **~23:15** - Restarted CSI sidecars (csi-attacher pods couldn't reach kubernetes API — `no route to host` from stale networking).
- **~23:20** - Cleaned duplicate Longhorn VolumeAttachment tickets blocking RWO volume attachment.
- **~23:25** - 3 volumes still stuck in `creating`/`faulted` (controller reconciliation loop). Scaled down longhorn-manager daemonset, patched volume status via k8s API status subresource to `detached`/`faulted`, restored managers.
- **~23:35** - All volumes attached. Restarted authentik (stale DNS from pre-fix era). Forgejo followed.
- **~23:40** - 92/92 pods running. Cluster fully recovered.

## What Happened

The incident began with enabling IPVS kube-proxy mode, but IPVS was not the root cause. The real problem was latent: keepalived VIPs (192.168.1.53, .54) were bound to the same interface (ens18) as flannel, and flannel's IP auto-detection was picking up VIPs as the node's "public IP." This generated incorrect host-gw routes cluster-wide, routing each node's pod traffic to the wrong host.

Under iptables kube-proxy mode, this was masked: iptables DNAT in PREROUTING rewrote destination addresses before routing decisions happened, so the stale routes were rarely hit. Switching to IPVS exposed the problem because IPVS hooks at NF_INET_LOCAL_IN (INPUT chain) — packets must first be routed correctly to reach the IPVS virtual server addresses on kube-ipvs0. The stale routes intercepted pod traffic before it reached INPUT, sending it out ens18 to the wrong node instead.

A second issue compounded this: NixOS's stateful firewall drops packets on INPUT that don't match an allowed service. With IPVS, pod→ClusterIP traffic arrives on INPUT via the cni0 bridge (with `bridge-nf-call-iptables=1`). The NixOS firewall dropped this traffic before IPVS could intercept it. This required an explicit firewall rule to accept pod CIDR → service CIDR traffic on cni0.

The fix required three layers:
1. `--flannel-external-ip` (server flag) + `--node-external-ip=<nodeIp>` (all nodes) — triggers the k3s CCM to set `flannel.alpha.coreos.com/public-ip-overwrite`, which flannel respects
2. `--flannel-iface=<iface>` — limits flannel to the correct interface (belt-and-suspenders)
3. NixOS firewall rule — allows pod→ClusterIP traffic on INPUT for IPVS

The Longhorn recovery was a cascading consequence. During the hours of broken pod networking, volumes detached, engines stopped, and the Longhorn controller entered stuck states. Recovery required: restarting stale instance-managers, cleaning duplicate VolumeAttachment tickets, force-patching volume status via the k8s API while the manager daemonset was scaled down, and restarting CSI sidecars with stale networking.

## Contributing Factors

- **Keepalived VIPs on the same interface as flannel.** This is the fundamental architectural issue. Flannel iterates all IPs on an interface and may choose any of them — including keepalived virtual IPs that float between nodes.
- **Flannel's IP auto-detection has no "prefer real IP" heuristic.** It picks the first IP it finds, which may be a VIP that doesn't belong to the node at all times.
- **`--flannel-iface` controls which interface, not which IP.** The flag name implies it would prevent VIP detection, but it doesn't — flannel still sees all IPs on that interface.
- **Manually setting `public-ip-overwrite` annotation is ignored by k3s flannel.** Only the CCM path (via `--node-external-ip`) works. This is undocumented.
- **IPVS mode changes packet flow through netfilter.** iptables kube-proxy DNATs in PREROUTING; IPVS intercepts in INPUT. This changes which firewall rules and routes matter, exposing latent routing issues.
- **NixOS firewall default-drops INPUT.** Standard for a host firewall, but incompatible with IPVS without explicit allow rules for pod traffic.
- **No flannel route monitoring or alerting.** The stale routes existed before IPVS was enabled but were masked. No monitoring would have caught them.
- **Long-running pods inherit stale networking after flannel fixes.** Instance-managers, CSI sidecars, and application pods all had pre-fix IPs and routing, requiring manual restarts.

## What I Was Wrong About

- **"IPVS broke pod networking"** — IPVS didn't break anything. It exposed pre-existing broken flannel routes that iptables mode had been masking. The routes were wrong the entire time.
- **"`--flannel-iface` will prevent VIP detection"** — It only controls which interface flannel uses, not which IP on that interface. VIPs on the same interface are still picked up.
- **"Setting the `public-ip-overwrite` annotation directly should work"** — k3s's embedded flannel ignores manually-set annotations. The annotation must be set by the CCM via `--node-external-ip`.
- **"Pod egress slowness was caused by MTU 1280 from the WireGuard tunnel"** — This was the diagnosis from the February HTTP/2 VXLAN postmortem and subsequent debugging. The actual cause was corrupted flannel routes sending pod traffic to wrong nodes. After fixing flannel, Flux reconcile dropped from minutes/timeouts to ~21 seconds. The MTU was a minor factor at most.
- **"Deleting engines/replicas/VolumeAttachments will unstick Longhorn volumes"** — The Longhorn controller's reconciliation loop is faster than manual API calls. Patching volume status gets overridden in milliseconds. The only way to break the cycle was to stop the controller entirely (scale down the daemonset), then patch.

## What Helped

- **tcpdump from `nix-shell -p tcpdump`** — Being able to temporarily install tcpdump without modifying system config was critical for tracing packet flow and discovering that SYN packets never left the node.
- **`/proc/net/nf_conntrack`** — When `conntrack` tool wasn't installed, the proc filesystem provided the same information.
- **`ip route get <pod-IP>`** — This single command revealed the duplicate routes immediately. The stale `via` route taking precedence over the `dev cni0` route was the smoking gun.
- **The flannel-backup/restore systemd services** — From the January flannel-subnet-env incident. These ensured flannel state survived the multiple k3s restarts during the fix.
- **k8s API status subresource** — Patching via the status subresource endpoint (`/apis/longhorn.io/v1beta2/.../status`) bypasses admission webhooks, allowing volume status patches even when the webhook is down.

## What Could Have Been Worse

- **The stale routes could have caused data corruption.** Pod traffic being misrouted to wrong nodes could theoretically have reached the wrong pod if CIDRs overlapped. In practice, the traffic was dropped at the destination because no matching pod existed, but the risk was there.
- **The Longhorn volume data could have been lost.** 7 volumes were faulted with 1/3 replicas. If the single remaining replica on theoden had been corrupted during the networking outage, the data (including forgejo git repos and authentik database) would have been gone. Single-replica volumes during an outage are a near-miss.
- **If the flannel fix had been deployed without `--flannel-external-ip`**, the stale routes would have regenerated on every k3s restart, requiring manual route deletion each time.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This is at least the fourth flannel-related incident (flannel-subnet-env-reboot, HTTP/2 VXLAN MTU, cni0 bridge MTU, and now VIP route corruption). The common thread: flannel's auto-detection and state management are fragile, and any change to the network (adding VIPs, changing MTU, switching backends) can corrupt the pod network in subtle ways that only manifest under specific traffic patterns.

The deeper pattern is **keepalived + flannel on the same interface**. These two systems both manipulate IP addresses on the interface and neither is aware of the other. The fix applied here (`--flannel-external-ip` + `--node-external-ip`) is robust, but the fact that it required discovering an undocumented interaction between three flags (`--flannel-iface`, `--flannel-external-ip`, `--node-external-ip`) suggests this is a fragile arrangement.

Additionally, **Longhorn with single-replica volumes during outages** is a recurring risk. Every networking incident cascades into stuck volumes because there's no redundancy to maintain availability during the disruption.

## Action Items

- [x] Deploy `--flannel-external-ip` + `--node-external-ip` + `--flannel-iface` to all nodes
- [x] Add NixOS firewall rule for IPVS pod→ClusterIP traffic
- [x] Add `nodeIp` and `flannelIface` options to k3s.nix module
- [x] Restart all stale instance-managers and CSI sidecars after flannel fix
- [ ] Add Prometheus alert for flannel route inconsistency (compare `flannel.alpha.coreos.com/public-ip` annotation against actual node IP)
- [ ] Increase Longhorn replica count from 1 to 2 for critical volumes (authentik-postgresql, forgejo, prometheus) to survive single-node outages
- [ ] Document the post-flannel-fix restart checklist: instance-managers, CSI sidecars, long-running app pods
- [ ] Consider separating keepalived VIPs onto a dedicated interface or loopback to avoid flannel IP conflicts entirely

## Lessons

- **When IPVS connections are stuck in SYN_RECV, check routing first.** IPVS requires correct routing to deliver packets to INPUT. Use `ip route get <pod-IP>` to verify the kernel's routing decision. Stale or duplicate routes are the most likely culprit.
- **`--flannel-iface` is not enough when keepalived VIPs are on the same interface.** You must also use `--flannel-external-ip` + `--node-external-ip` to force flannel to use the correct IP via the k3s CCM annotation.
- **Switching kube-proxy modes changes which netfilter hooks matter.** iptables mode uses PREROUTING (DNAT before routing); IPVS mode uses INPUT (routing must be correct first). Latent routing issues hidden by iptables mode will surface with IPVS.
- **After any flannel routing fix, restart ALL long-running pods.** Instance-managers, CSI sidecars, and application pods all inherit stale networking. A clean restart is not optional.
- **To break a Longhorn controller reconciliation loop:** scale down the longhorn-manager daemonset (impossible nodeSelector), patch the volume status via the k8s API status subresource, then restore the daemonset. Direct patches while the controller is running get overridden in milliseconds.
- **Previous postmortem diagnoses can be wrong.** The February HTTP/2 VXLAN postmortem attributed Flux slowness to MTU issues. The actual cause was corrupted flannel routes — which were present at the time but not identified. Always question inherited diagnoses when new evidence appears.
