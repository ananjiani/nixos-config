---
date: 2026-02-14
title: Rivendell Realtek NIC inbound connectivity death — two root causes
severity: major
duration: ~12h (investigation across three sessions, 7 nixos-anywhere reinstalls)
systems: [rivendell, networking, deploy-rs, prometheus, tailscale]
tags: [networking, hardware, realtek, r8169, offloading, tailscale, bare-metal]
commit: https://codeberg.org/ananjiani/infra/commit/1178a88
---

## Summary

Rivendell (Trycoo WI6 N100 HTPC, bare metal) suffered two distinct NIC failure modes after provisioning. **Issue 1**: inbound connectivity dropped after ~7 minutes due to RX buffer overflow from hardware offloading on the Realtek RTL8168 NIC's 256-entry ring buffer. **Issue 2**: after fixing offloading, the NIC still died at exactly ~11-12 minutes due to Tailscale's netfilter/routing modifications triggering a driver bug. Investigation spanned 3 sessions, 7 boots, and systematically eliminated 9 hypotheses before isolating Tailscale as the second root cause. Resolution: disable hardware offloading + disable Tailscale on rivendell.

## Timeline

All times CST.

### Session 1 — EEE hypothesis (Feb 12)

- **~21:00** — nixos-anywhere successfully provisions rivendell. Kodi is visible on the TV, SSH works initially.
- **~21:15** — First connectivity drop noticed. SSH to rivendell stops working.
- **~22:00** — Deployed boromir, samwise, theoden to propagate DNS rewrites and keepalived peers.
- **~22:15** — deploy-rs to rivendell copies closure but activation fails: Tailscale `tailscaled-set` rejects `--exit-node=boromir`. Magic rollback triggers after 240s.
- **~22:30** — Fixed `useExitNode = null`. Attempted deploy again — connection drops mid-copy.

### Session 2 — Offloading fix (Feb 13)

- **~13:07** — Started background monitor script. Key finding: rivendell never lost gateway connectivity — all 140 pings succeeded. Drop was inbound-only.
- **~13:30** — Added `ethtool` and `disable-eee` systemd service.
- **~14:30** — Connectivity drops again after 10 min. EEE alone was insufficient.
- **~14:45** — Added `pcie_aspm=off` kernel param. Still drops at ~7 min.
- **~15:45** — HolmesGPT analysis via Prometheus reveals: three uptime windows, each ~7 min, with ~450 rx_dropped per 3.5 min scrape interval. Zero rx_errors.
- **~16:20** — Disabled all hardware offloading (TSO/GRO/GSO/SG/rx/tx). RX ring buffer max confirmed at 256 entries.
- **~16:34–16:49** — **15-minute soak test passes.** 30/30 polls, rx_missed: 0. **Issue 1 resolved.**

### Session 3 — NIC still dying (Feb 13-14)

With offloading fixed, rivendell survived the 7-min mark but a new failure pattern emerged at ~11-12 minutes.

- **Feb 13 ~22:35** — Boot 1: rivendell up for 69 min, killed by deploy-rs activation (not a NIC failure).
- **Feb 14 ~00:15** — Boot 2: 7 min, killed by deploy-rs rollback loop.
- **Feb 14 ~01:17** — Boot 3: **NIC dies at 11 min.** Full k3s + keepalived + Tailscale running.
- **Feb 14 ~02:11** — Boot 4: **NIC dies at 11 min.** Added UDP GRO exclusion for Tailscale.
- **Feb 14 ~03:06** — Boot 5: **NIC dies at 12 min.** Disabled k3s and keepalived entirely. k3s ruled out.
- **Feb 14 ~19:00** — Prometheus thermal analysis: 54C at death vs 58C survived 69 min in Boot 1. Thermal ruled out.
- **Feb 14 ~19:30** — Investigated PCI runtime PM. Discovered `pcie_aspm=off` only disables link-level power states; kernel runtime PM independently puts PCI devices into D3hot.
- **Feb 15 ~01:26** — Boot 6: **NIC dies at 11 min.** PCI runtime PM confirmed `active` (D0) at every poll until death. D3hot ruled out.
- **Feb 15 ~01:50** — Disabled Tailscale entirely.
- **Feb 15 ~02:00** — Boot 7: Deployed with no Tailscale, no k3s, no keepalived. Started dmesg monitoring script.
- **Feb 15 ~02:01–02:21+** — **Boot 7 survives 21+ minutes with zero issues.** NIC completely stable. `systemd-tmpfiles-clean.timer` fired at 12 min — NIC survived it fine. **Issue 2 root cause: Tailscale.**

## What Happened

Two separate failure modes overlapped on the same NIC:

### Issue 1: RX buffer overflow from hardware offloading (~7 min death)

The Realtek RTL8168 has a hardware RX ring buffer maximum of only 256 entries. With offloading enabled, the DMA engine caused the buffer to overflow at ~2 drops/sec. After ~7 minutes, enough drops accumulated to make the NIC unresponsive to inbound traffic. Disabling TSO/GRO/GSO/SG/rx/tx checksumming via ethtool eliminated this.

### Issue 2: Tailscale netfilter interaction kills r8169 (~11 min death)

After fixing offloading, the NIC survived past 7 min but died consistently at ~11-12 min. Prometheus data across 6 boots showed: `rx_fifo=0` (no hardware overflow), `rx_err=0`, carrier never drops, CPU 91-98% idle, temperature normal — then instant death (Prometheus scrape goes from 0.05s to 10s timeout in one step, no graceful degradation).

Systematic elimination across Boots 3-7:

| Boot | Duration | Config | Result |
|------|----------|--------|--------|
| 3 | 11 min | k3s + keepalived + Tailscale | Dead |
| 4 | 11 min | + UDP GRO excluded | Dead |
| 5 | 12 min | No k3s/keepalived, Tailscale on | Dead |
| 6 | 11 min | + PCI runtime PM fixed | Dead |
| 7 | **21+ min** | **No Tailscale** | **Stable** |

### Follow-up: k3s + keepalived re-enabled (Feb 15)

After confirming Tailscale as the sole netfilter culprit, keepalived + AdGuard DNS were re-enabled (30+ min soak, NIC stable). k3s was then re-enabled as an agent node:

| Test | Duration | Config | Result |
|------|----------|--------|--------|
| Keepalived+AdGuard | 30+ min | VRRP + DNS, no Tailscale | **Stable** |
| k3s agent | 22+ min | 14 containers, 23 KUBE iptables chains | **Stable** |

k3s adds KUBE-SERVICES chains, ClusterIP DNAT rules, masquerade, and connection tracking — yet the NIC handled all of it without issue. This narrows the root cause to Tailscale's **mark-based policy routing** specifically (`fwmark 0x80000/0xff0000`, `ip rule` entries, routing table 52, MagicDNS DNAT), not conventional iptables DNAT/masquerade.

Tailscale modifies the kernel network stack in several ways: nftables rules for tunnel routing, policy routing via `ip rule`, and UDP GRO forwarding optimization. The r8169 driver + RTL8168h chip combination is fragile, and Tailscale's netfilter packet processing path triggers a driver bug that causes complete inbound connectivity loss after ~11 minutes.

### Red herrings investigated

1. **EEE (Energy Efficient Ethernet)** — Appeared to fix in short test, drops returned. Was a contributing factor to Issue 1 but not the sole cause.
2. **PCIe ASPM** — `pcie_aspm=off` added, didn't help with either issue.
3. **r8169 modprobe params** — `eee_enable=0` silently ignored (r8168-only option).
4. **k3s iptables/conntrack** — Boot 5 died without k3s (conntrack at 5-31, minimal).
5. **Thermal throttling** — Prometheus thermal data: 54C at death vs 58C survived 69 min.
6. **PCI runtime PM (D3hot)** — Added `power/control=on` udev rule. Boot 6 confirmed `runtime_status=active` at every poll until death.
7. **UDP GRO forwarding** — Excluded enp1s0 from Tailscale's UDP GRO optimization. Boot 4 still died.
8. **systemd-tmpfiles-clean.timer** — Fires at ~12 min after boot (suspicious timing), but Boot 7 survived it fine.
9. **RX ring buffer increase** — Hardware max is 256, cannot be increased.

## Contributing Factors

- **Realtek RTL8168h has a 256-entry RX ring buffer maximum.** Extremely small for any server workload.
- **r8169 driver's hardware offloading has known issues on budget Realtek NICs.** Documented across Proxmox, Arch Linux, and multiple bug trackers.
- **Tailscale's netfilter modifications trigger an r8169 driver bug.** The specific mechanism is unclear, but the interaction between Tailscale's nftables rules and the r8169 driver's RX path causes complete inbound loss after ~11 min.
- **Boot 1 surviving 69 min created a misleading baseline.** This was the initial install where Tailscale hadn't fully engaged its auth flow / netfilter setup, masking Issue 2.
- **The two failure modes had identical symptoms.** Both presented as inbound-only connectivity loss with outbound still working. Only the timing differed (7 min vs 11 min).
- **Bare metal Realtek vs VM virtio.** All other servers use virtio NICs which have none of these issues.

## What I Was Wrong About

- **"Disabling offloading fully fixed the NIC."** The 15-minute soak test in Session 2 passed, but a longer test would have revealed the ~11 min Tailscale failure. The offloading fix only resolved Issue 1.
- **"k3s iptables rules are causing the 11-min death."** k3s was the obvious suspect since it adds extensive nftables rules, but Boot 5 eliminated it. Follow-up testing on Feb 15 confirmed k3s agent (14 containers, 23 KUBE chains) runs indefinitely without NIC issues.
- **"PCI runtime PM (D3hot) is suspending the NIC."** The kernel runtime PM framework can independently put PCI devices into D3hot even with ASPM off. This was a reasonable hypothesis, but Boot 6 proved the device stayed in D0 the entire time.
- **"systemd-tmpfiles-clean.timer at 12 min is suspiciously correlated."** Coincidental timing — Boot 7 survived the timer firing with no issues.
- **"The RX buffer can be increased."** Hardware max is 256. `ethtool -G` silently fails.
- **"eee_enable=0 is a valid r8169 parameter."** It's r8168-only (out-of-tree driver).

## What Helped

- **Prometheus + node_exporter as the primary diagnostic tool.** Once added to scrape targets, Prometheus provided per-boot metrics including rx_fifo, rx_err, thermal data, and scrape timing — all from an external observer that didn't depend on SSH to rivendell.
- **Systematic variable isolation.** Disabling one service at a time (k3s, keepalived, Tailscale) across separate boots was the only way to identify Tailscale as the culprit.
- **The dmesg monitoring script.** Captured full initial dmesg, NIC state, systemd timers, and polled every 10s with `dmesg --since`. Confirmed no kernel errors at the moment of death and ruled out tmpfiles-clean.
- **nixos-anywhere as a recovery path.** Used 7 times across three sessions. When deploy-rs can't reach the target, nixos-anywhere from a live USB bypasses the problem entirely.
- **HolmesGPT via Prometheus (Session 2).** Identified the RX buffer overflow pattern from kubelet/cAdvisor metrics when SSH was dead.

## What Could Have Been Worse

- If the NIC failure had been intermittent rather than deterministic (~11 min), it could have taken weeks to diagnose. The consistent timing made it testable.
- If Tailscale had been removed earlier in the investigation, we might have missed the offloading issue entirely (it would have manifested later under load).

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Two patterns emerged:

1. **Budget Realtek NICs are incompatible with Tailscale's mark-based policy routing.** The r8169 driver cannot handle Tailscale's fwmark/policy routing modifications specifically — conventional iptables (k3s KUBE-SERVICES, DNAT, masquerade) and VRRP (keepalived) work fine. This limits Tailscale usage on bare metal hosts with Realtek NICs, but doesn't preclude k3s or other standard netfilter users. Future bare metal purchases should still prioritize Intel I225-V or similar.
2. **15-minute soak tests give false confidence.** The offloading fix passed a 15-minute test but the Tailscale issue manifested at 11 min. Soak tests should run for at least 30 minutes, preferably 1 hour.

## Action Items

- [x] Add `ethtool` to rivendell's system packages
- [x] Add `nic-offloading` systemd service that disables EEE and hardware offloading on boot
- [x] Add `pcie_aspm=off` kernel parameter
- [x] Add PCI runtime PM udev rule (`ATTR{power/control}="on"` for r8169)
- [x] Add PCI runtime PM override in systemd service
- [x] Add rivendell to Prometheus node_exporter scrape targets
- [x] Disable Tailscale on rivendell (permanently)
- [x] Re-enable k3s agent + keepalived + AdGuard on rivendell (verified safe via 22+ min soak test)
- [x] Document hardware quirk in MEMORY.md
- [ ] Consider USB Ethernet adapter if Tailscale is needed later
- [ ] Consider extracting NIC tuning into a reusable NixOS module if another bare metal host is added
- [ ] Evaluate `--netfilter-mode=off` or userspace networking mode for Tailscale on Realtek NICs

## Lessons

- **Two overlapping failure modes with identical symptoms can mask each other.** Both offloading overflow and Tailscale interaction presented as inbound-only loss. Fixing one revealed the other at a different time threshold.
- **Systematic elimination is the only reliable approach for hardware/driver bugs.** Intuition and log analysis failed — only disabling services one at a time across separate boots proved the cause.
- **Budget Realtek NICs are fragile under Tailscale's policy routing, not netfilter in general.** The r8169 driver + RTL8168h chip cannot handle Tailscale's fwmark-based routing, but conventional iptables (k3s, keepalived) work fine. The failure is specific to Tailscale's packet marking path, not netfilter load broadly.
- **Prometheus is more reliable than SSH for diagnosing NIC issues.** SSH depends on the NIC being healthy. An external Prometheus scraper provides observability even during failure.
- **Boot 1 outliers can be misleading.** The 69-minute Boot 1 survival was due to Tailscale not being fully initialized, not because the NIC was healthy. Always confirm stability under steady-state conditions.
- **Soak tests must exceed 2x the failure window.** A 15-minute soak test can miss an 11-minute failure if the first issue is fixed but the second isn't.
