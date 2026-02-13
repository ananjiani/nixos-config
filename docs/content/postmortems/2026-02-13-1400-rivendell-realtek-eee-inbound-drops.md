---
date: 2026-02-13
title: Rivendell intermittent inbound connectivity drops from Realtek NIC offloading
severity: moderate
duration: ~6h (investigation across two sessions), multiple nixos-anywhere reinstalls
systems: [rivendell, networking, deploy-rs, prometheus]
tags: [networking, hardware, realtek, r8169, offloading, bare-metal]
commit: https://codeberg.org/ananjiani/infra/commit/82e1a45
---

## Summary

Rivendell (Trycoo WI6 N100 HTPC, bare metal) lost inbound network connectivity after exactly ~7 minutes of uptime — consistently, across multiple reinstalls. Other hosts couldn't reach it, but rivendell could still reach the gateway and the internet. Initial investigation blamed EEE (Energy Efficient Ethernet), but disabling EEE alone was insufficient. Adding PCIe ASPM disable and modprobe params also didn't fix it. The actual root cause was **hardware offloading** (TSO, GRO, GSO, scatter-gather, rx/tx checksumming) on the Realtek RTL8168 NIC with only 256 RX ring buffer entries. Disabling offloading via ethtool eliminated the drops entirely.

## Timeline

All times CST.

### Session 1 — EEE hypothesis

- **Feb 12 ~21:00** — nixos-anywhere successfully provisions rivendell. Kodi is visible on the TV, SSH works initially.
- **Feb 12 ~21:15** — First connectivity drop noticed. SSH to rivendell stops working.
- **Feb 12 ~22:00** — Deployed boromir, samwise, theoden to propagate DNS rewrites and keepalived peers.
- **Feb 12 ~22:15** — deploy-rs to rivendell copies closure but activation fails: Tailscale `tailscaled-set` rejects `--exit-node=boromir`. Magic rollback triggers after 240s.
- **Feb 12 ~22:30** — Fixed `useExitNode = null`. Attempted deploy again — connection drops mid-copy.

### Session 2 — Deeper investigation

- **Feb 13 ~13:07** — Started background monitor script on rivendell logging every 5 seconds.
- **Feb 13 ~13:22** — Retrieved monitor log. Key finding: **rivendell never lost gateway connectivity** — all 140 pings succeeded. The drop was inbound-only.
- **Feb 13 ~13:30** — Added `ethtool` and `disable-eee` systemd service. Pivoted to nixos-anywhere.
- **Feb 13 ~13:58** — Rivendell boots with EEE fix. 10-minute stress test passes (60/60 pings, 50MB transfer).
- **Feb 13 ~14:30** — Connectivity drops again. EEE alone was insufficient.
- **Feb 13 ~14:45** — Added `pcie_aspm=off` kernel param and `options r8169 eee_enable=0` modprobe config. Reinstalled via nixos-anywhere.
- **Feb 13 ~15:15** — Started 15-minute soak test. Rivendell drops again after ~7 minutes.
- **Feb 13 ~15:30** — Used HolmesGPT (via k8s API) to query Prometheus metrics from the brief uptime windows.

### Session 2 — HolmesGPT diagnosis and fix

- **Feb 13 ~15:45** — HolmesGPT analysis reveals: rivendell came up exactly three times, each lasting ~7 minutes. `container_network_receive_packets_dropped_total` on enp1s0 increased by **~420-450 drops per 3.5-minute scrape interval** (~2 drops/sec). Zero receive errors. Also discovered node_exporter wasn't being scraped (missing from Prometheus targets).
- **Feb 13 ~16:00** — Added rivendell to Prometheus scrape targets. Researched r8168 out-of-tree driver — marked broken for kernel >= 6.13, rivendell runs 6.18.10.
- **Feb 13 ~16:20** — New approach: disable hardware offloading (rx/tx checksumming, scatter-gather, TSO, GRO, GSO) via ethtool. Also attempted RX ring buffer increase.
- **Feb 13 ~16:30** — Reinstalled via nixos-anywhere with new tuning service.
- **Feb 13 ~16:34** — Diagnostics reveal: RX ring buffer hardware max is **256 entries** (can't be increased), `eee_enable` modprobe param was silently ignored (not a valid r8169 option), but **all offloading successfully disabled**.
- **Feb 13 ~16:34–16:49** — **15-minute soak test: 30/30 polls, rx_missed: 0 the entire time, 0 errors.** Past the 7-minute death mark with zero issues.

## What Happened

After provisioning rivendell, the machine would boot and be reachable for exactly ~7 minutes, then silently become unreachable from other hosts. The failure was consistent and reproducible across four separate nixos-anywhere installs.

### Red herrings

The investigation went through three incorrect hypotheses before finding the root cause:

1. **EEE (Energy Efficient Ethernet)** — Disabling EEE via ethtool appeared to fix the issue initially (a 10-minute stress test passed), but longer soak tests showed it still dropped.
2. **PCIe ASPM** — Adding `pcie_aspm=off` kernel parameter didn't help.
3. **r8169 modprobe params** — `options r8169 eee_enable=0` was silently ignored because `eee_enable` is an r8168 (out-of-tree driver) option, not valid for the in-kernel r8169 driver.

### The breakthrough: Prometheus metrics via HolmesGPT

When SSH was unreachable, we used HolmesGPT (deployed on the k8s cluster) to query Prometheus. Since rivendell runs a k3s agent, kubelet/cAdvisor metrics were available from port 10250 during the brief uptime windows. HolmesGPT found:

- Three uptime periods, each exactly ~7 minutes
- `container_network_receive_packets_dropped_total` on enp1s0 increased by **~420-450 drops per 3.5-minute scrape interval** (monotonically)
- **Zero receive errors** — only drops, indicating RX buffer overflow, not packet corruption
- node_exporter (port 9100) was never scraped because rivendell was missing from the Prometheus scrape targets

### Root cause: hardware offloading + tiny RX ring buffer

The Realtek RTL8168 NIC has a hardware RX ring buffer maximum of only **256 entries**. With hardware offloading enabled (TSO, GRO, GSO, scatter-gather, rx/tx checksumming), the NIC's DMA engine was processing packets in a way that caused the 256-entry buffer to overflow at a steady ~2 drops/sec rate. After ~7 minutes, enough drops accumulated to make the NIC unresponsive to inbound traffic.

Disabling all hardware offloading shifts packet processing to the CPU. The N100's CPU has plenty of headroom for this workload, and without the offload engine's DMA issues, the 256-entry RX buffer is sufficient for normal k3s + HTPC traffic.

## Contributing Factors

- **Realtek RTL8168 has a 256-entry RX ring buffer maximum.** This is extremely small for a server running k3s with MetalLB, keepalived, and AdGuard. Most modern NICs support 4096+.
- **The r8169 driver's hardware offloading implementation has known issues on budget Realtek NICs.** The Proxmox forums, Arch Linux forums, and multiple bug trackers document rx_missed/dropped issues specifically with r8168/r8169 hardware offloading.
- **`ethtool` was not in the initial system packages.** Without ethtool, there was no way to inspect or control NIC-level features from the running system.
- **node_exporter wasn't being scraped by Prometheus.** Rivendell was missing from the `nixos-node-exporter` ScrapeConfig, so `node_network_*` metrics were never collected. We had to rely on cAdvisor/kubelet metrics, which only expose container-level network stats.
- **The r8168 out-of-tree driver is broken on kernel >= 6.13.** This would have been the standard fix, but rivendell runs kernel 6.18.10 (NixOS 25.11 unstable).
- **Bare metal has different NIC behavior than Proxmox VMs.** All other servers use virtio NICs which don't have offloading or EEE issues.

## What I Was Wrong About

- **"This is an EEE issue."** EEE disabling appeared to work in a short 10-minute test but the drops returned. The asymmetric connectivity pattern (outbound works, inbound doesn't) happens to look identical for both EEE and offloading issues.
- **"Adding ASPM disable and modprobe params will fix it."** Three power-management mitigations (EEE, ASPM, modprobe) all missed the actual cause. The drops were from offloading-related DMA issues, not power management.
- **"eee_enable=0 is a valid r8169 module parameter."** It's an r8168 (out-of-tree driver) option. The in-kernel r8169 silently ignores unknown parameters with a dmesg warning.
- **"The RX ring buffer can be increased."** The hardware max is 256 entries. `ethtool -G enp1s0 rx 4096` silently fails.

## What Helped

- **HolmesGPT querying Prometheus.** When SSH was dead, HolmesGPT could still access kubelet/cAdvisor metrics from rivendell's brief uptime windows. The monotonic packet drop pattern was the smoking gun.
- **The background monitor script.** Logging gateway ping, NIC state, iptables count every 5 seconds proved the drops were inbound-only.
- **nixos-anywhere as a recovery path.** Used four times across two sessions. When deploy-rs can't reach the target, nixos-anywhere from a live USB bypasses the problem entirely.
- **Prometheus + cAdvisor metrics from k3s.** Even though node_exporter wasn't scraped, the kubelet metrics exposed `container_network_receive_packets_dropped_total` which revealed the drop pattern.

## Is This a Pattern?

- [x] One-off: Correct and move on
- [ ] Pattern: Revisit the approach

Specific to bare metal Realtek RTL8168 hardware. The VM fleet uses virtio NICs which don't have offloading or EEE issues. However, the missing Prometheus scrape target is a process gap — new hosts should be added to both the NixOS config and the Prometheus scrape targets simultaneously.

## Action Items

- [x] Add `ethtool` to rivendell's system packages
- [x] Add `realtek-nic-tuning` systemd service that disables EEE and hardware offloading on boot
- [x] Add `pcie_aspm=off` kernel parameter
- [x] Reinstall rivendell via nixos-anywhere with fixes baked in
- [x] Verify stable connectivity with 15-minute soak test (30/30 polls, 0 rx_missed)
- [x] Add rivendell to Prometheus node_exporter scrape targets
- [x] Document hardware quirk in MEMORY.md
- [ ] Consider extracting NIC tuning into a reusable NixOS module if another bare metal host is added

## Lessons

- **Zero rx_errors + high rx_dropped = RX buffer overflow, not corruption.** This distinction points to offloading/DMA issues rather than electrical or signal problems. Check `ethtool -S` counters, not just `ip -s link`.
- **Hardware offloading can be harmful on budget NICs.** TSO, GRO, GSO, and scatter-gather are designed to reduce CPU load, but on Realtek RTL8168 with only 256 RX ring buffer entries, they cause more harm than good. Disabling them and letting the CPU handle packet processing is the right trade-off.
- **The r8168 out-of-tree driver is not a viable fix on modern kernels.** It's broken for kernel >= 6.13. The in-kernel r8169 with tuned ethtool settings is the supported path forward.
- **Always add new hosts to Prometheus scrape targets.** Enabling node_exporter in NixOS config is only half the story — Prometheus needs to know about it too. The missing scrape target cost us visibility during the investigation.
- **HolmesGPT + Prometheus is a powerful debugging combination for unreachable hosts.** When you can't SSH into a node, querying metrics from its brief uptime windows via an AI investigator can reveal patterns you'd never catch manually.
- **Short stress tests can give false confidence.** The EEE-only fix passed a 10-minute test but failed at 15 minutes. Always soak test for at least 2x the expected failure window.
