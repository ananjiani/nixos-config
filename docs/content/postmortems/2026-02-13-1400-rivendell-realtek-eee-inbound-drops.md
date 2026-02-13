---
date: 2026-02-13
title: Rivendell intermittent inbound connectivity drops from Realtek EEE
severity: moderate
duration: ~3h (investigation), ~24h (total time to resolve including multiple reboots)
systems: [rivendell, networking, deploy-rs]
tags: [networking, hardware, realtek, r8169, eee, bare-metal]
commit: https://codeberg.org/ananjiani/infra/commit/eeddc6b
---

## Summary

Rivendell (Trycoo WI6 N100 HTPC, bare metal) lost inbound network connectivity intermittently — other hosts couldn't reach it, but rivendell could still reach the gateway and the internet. The issue appeared 7–10 minutes after each boot and persisted until the next reboot. This blocked deploy-rs from delivering configuration fixes and caused multiple hours of debugging across two sessions. The root cause was Energy Efficient Ethernet (EEE) on the Realtek RTL8168 NIC (r8169 driver), which put the PHY into a low-power state that stopped responding to incoming ARP requests.

## Timeline

All times CST.

- **Feb 12 ~21:00** - nixos-anywhere successfully provisions rivendell. Kodi is visible on the TV, SSH works initially.
- **Feb 12 ~21:15** - First connectivity drop noticed. SSH to rivendell stops working. Rivendell can still be reached sporadically after reboots.
- **Feb 12 ~21:30** - Attempted deploy-rs to push k3s agent fix. DNS resolution for `rivendell.lan` fails — AdGuard DNS rewrites not yet deployed to other servers.
- **Feb 12 ~22:00** - Deployed boromir, samwise, theoden to propagate DNS rewrites and keepalived peers. DNS now resolves `rivendell.lan`.
- **Feb 12 ~22:15** - deploy-rs to rivendell succeeds in copying closure but activation fails: Tailscale's `tailscaled-set` rejects `--exit-node=boromir`. Magic rollback triggers after 240s.
- **Feb 12 ~22:30** - Fixed `useExitNode = null` in rivendell config. Attempted deploy again — connection drops mid-copy. Multiple reboots and retry attempts follow.
- **Feb 13 ~13:07** - Fresh session. Started background network monitor on rivendell logging every 5 seconds to `/tmp/deploy-monitor.log`.
- **Feb 13 ~13:11** - Attempted deploy-rs again. Connection drops during nix copy phase.
- **Feb 13 ~13:22** - Retrieved monitor log. Key finding: **rivendell never lost gateway connectivity** — all 140 pings to 192.168.1.1 succeeded. The drop was inbound-only.
- **Feb 13 ~13:24** - SSH'd in during a connectivity window. Identified NIC driver as `r8169` (Realtek RTL8168), noticed 94 `rx_dropped` packets, and confirmed `ethtool` was not installed.
- **Feb 13 ~13:30** - Added `ethtool` package and `disable-eee` systemd oneshot service to rivendell config. deploy-rs fails again due to connectivity drop.
- **Feb 13 ~13:55** - Pivoted to nixos-anywhere from live USB installer. Clean install with EEE fix baked in.
- **Feb 13 ~13:58** - Rivendell boots with new config. `disable-eee.service` runs successfully. EEE confirmed disabled via `ethtool --show-eee`.
- **Feb 13 ~14:08** - 10+ minutes uptime with zero connectivity drops. 60-second sustained ping test: 60/60, 0% loss. 50MB bulk SSH transfer completes without interruption.

## What Happened

After provisioning rivendell with nixos-anywhere, the machine would boot and be reachable for roughly 7–10 minutes, then silently drop off the network from other hosts' perspective. From rivendell's own perspective, everything was fine — it could ping the gateway, resolve DNS, and reach the internet. But no other machine on the LAN could reach rivendell via ping, SSH, or any protocol.

The initial debugging sessions chased several red herrings: kube-router iptables rules, NixOS nftables firewall configuration, k3s agent networking, and ARP table issues on the router. None of these were the cause.

The breakthrough came from the background monitor script, which logged rivendell's gateway ping, NIC link state, iptables rule count, and k3s status every 5 seconds. After a "drop" event where the desktop could no longer reach rivendell, the monitor showed rivendell had maintained uninterrupted gateway connectivity the entire time. This proved the issue was purely one-directional: outbound from rivendell worked, inbound to rivendell didn't.

This pattern — asymmetric connectivity where outbound works but inbound fails — is the hallmark of an EEE issue on Realtek NICs. EEE (IEEE 802.3az) saves power by putting the PHY into a low-power idle state between packet bursts. On r8169 hardware, this low-power state can cause the NIC to stop responding to incoming ARP requests from the upstream switch. Other hosts' ARP entries for rivendell expire and can't be refreshed, so they can't deliver frames to rivendell. But rivendell's own outbound traffic works because transmitting wakes the PHY, and its own ARP entries for the gateway stay valid.

The fix was a systemd oneshot service that runs `ethtool --set-eee enp1s0 eee off` on boot. Since deploy-rs couldn't reliably deliver this fix (the connection kept dropping mid-transfer), we used nixos-anywhere from a live USB to do a clean install with the fix baked in from the start.

## Contributing Factors

- **Realtek RTL8168 (r8169 driver) has well-known EEE issues.** The r8169 driver's EEE implementation on certain chipsets is aggressive about entering low-power states, which breaks inbound ARP on some switch/NIC combinations.
- **`ethtool` was not included in the system packages.** Without ethtool, there was no way to inspect or disable EEE from the running system, delaying diagnosis.
- **The failure mode is silent and asymmetric.** There are no kernel errors, no dmesg messages, and no NIC link state changes. The NIC reports "UP" and rivendell's own outbound traffic works. This makes it look like a firewall or routing issue on first inspection.
- **deploy-rs requires sustained SSH connectivity.** The nix copy phase transfers the full closure over SSH, which can take minutes. With connectivity dropping after 7–10 minutes, the window wasn't reliable enough for deploy-rs to complete.
- **Bare metal has different NIC behavior than Proxmox VMs.** All other servers in the fleet are Proxmox VMs with virtio NICs, which don't have EEE. This was the first bare metal server, so EEE issues hadn't been encountered before.

## What I Was Wrong About

- **"This is a firewall or iptables issue."** The initial investigation focused heavily on kube-router iptables rules, NixOS nftables configuration, and keepalived. The iptables rule count did jump from 270 to 287 mid-session, but this turned out to be normal keepalived startup — it had nothing to do with the drops.
- **"The NIC is going down or the driver is crashing."** The monitor proved the NIC stayed UP with a stable link the entire time. The r8169 driver was fine — it was the PHY's power management, not the driver itself.
- **"If rivendell can ping the gateway, the network is fine."** Outbound connectivity doesn't prove inbound works. EEE specifically breaks the inbound path while leaving outbound functional. This was the wrong test to determine health.
- **"deploy-rs will work if I just catch the right timing window."** Multiple attempts to deploy during brief connectivity windows all failed because the transfer took longer than the window. The right approach was nixos-anywhere, which doesn't depend on the target's existing NIC configuration.

## What Helped

- **The background monitor script.** Logging gateway ping, NIC state, iptables count, and k3s status every 5 seconds was the key to diagnosing the one-directional nature of the failure. Without this, we could have spent much longer chasing symmetric-failure hypotheses.
- **nixos-anywhere as a fallback.** When deploy-rs couldn't deliver the fix due to the connectivity issue, nixos-anywhere from a live USB bypassed the problem entirely. The live installer has its own NIC configuration without EEE issues.
- **The SOPS age key extra-files were still in /tmp.** The nixos-anywhere `--extra-files` directory from the initial provisioning was still present, so the reinstall didn't require recreating secrets.
- **deploy-rs magic rollback on the Tailscale failure.** When the first deploy attempt activated but Tailscale failed, deploy-rs automatically rolled back after 240 seconds, leaving rivendell in a bootable state rather than stuck with a broken config.

## What Could Have Been Worse

- **If the connectivity drops had also affected outbound traffic**, rivendell would have been completely unreachable and we couldn't have gathered any diagnostics without physical console access.
- **If the live USB installer had the same EEE behavior**, nixos-anywhere would have also failed and we'd have needed to configure EEE settings in the installer environment manually.
- **If this had been a remote/headless server without physical access**, we wouldn't have been able to boot from a live USB as a recovery path.

## Is This a Pattern?

- [x] One-off: Correct and move on
- [ ] Pattern: Revisit the approach

This is specific to bare metal Realtek RTL8168 hardware. The VM fleet uses virtio NICs which don't have EEE. Unless another bare metal host is added with a Realtek NIC, this shouldn't recur. The fix (ethtool systemd oneshot) is a standard approach for r8169 EEE issues and is well-documented in the Linux networking community.

However, if more bare metal hosts are added in the future, it would be worth adding a generic "NIC tuning" module that can disable EEE, set ring buffer sizes, etc., per host.

## Action Items

- [x] Add `ethtool` to rivendell's system packages
- [x] Add `disable-eee` systemd oneshot service that disables EEE on boot
- [x] Reinstall rivendell via nixos-anywhere with the fix baked in
- [x] Verify stable connectivity with sustained ping and bulk transfer tests
- [x] Document hardware quirk in MEMORY.md for future reference
- [ ] Consider extracting NIC tuning into a reusable NixOS module if another bare metal host is added

## Lessons

- **Asymmetric connectivity (outbound works, inbound doesn't) on Realtek NICs points to EEE.** This is the first thing to check when r8169 hardware exhibits intermittent inbound drops with no kernel errors.
- **Always include `ethtool` on bare metal systems.** It's the only way to inspect and control NIC-level features like EEE, ring buffers, and offload settings. Without it, you're debugging blind.
- **Background monitoring scripts are invaluable for intermittent issues.** A 5-second polling loop that logs multiple system state dimensions will tell you exactly what changed at the moment of failure — even if you can't be watching at that exact moment.
- **nixos-anywhere is a viable recovery path when deploy-rs can't reach the target.** If the target's existing NIC configuration is the problem, deploy-rs inherits that problem. nixos-anywhere from a live USB sidesteps it entirely.
- **Don't assume VM-fleet experience transfers to bare metal.** Virtio NICs in Proxmox VMs have none of the power management quirks that physical Realtek NICs do. First bare metal host means first encounter with a whole class of hardware issues.
