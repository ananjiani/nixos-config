---
date: 2026-05-21
title: UPS graceful shutdown architecture (NUT on Proxmox only)
status: accepted
supersedes:
superseded_by:
systems: [nut, proxmox, k3s, prometheus, ntfy, rohan, gondor, the-shire, theoden, boromir, samwise, frodo]
tags: [infrastructure, power, shutdown, monitoring]
---

## Context and Problem Statement

A single CyberPower CP1500PFCRM2U UPS (USB-connected) protects three Proxmox hosts (rohan, gondor, the-shire) and their VMs. Rohan runs theoden (k3s server + NFS + CI/CD), gondor runs boromir (k3s server + GPU workloads), and the-shire runs samwise (k3s server + Zigbee2MQTT) and frodo (Home Assistant OS). All three k3s nodes depend on graceful drain to avoid data corruption and pod scheduling chaos. Without a coordinated shutdown, a power outage kills everything simultaneously — k3s etcd can lose quorum mid-write, NFS clients lose their server mid-IO, and pods don't get rescheduled. The UPS provides ~10-20 minutes of runtime at current load, which is enough time for a clean shutdown cascade if triggered promptly. Rivendell (bare metal HTPC) is on separate power and excluded from this architecture. The network switch (managed, same VLAN for all hosts) is on the same UPS as the Proxmox hosts, but the router is not — it is physically too far from the UPS for an extension cord.

## Decision Drivers

- k3s etcd and NFS data integrity — must drain nodes and unmount cleanly before power loss
- Operational simplicity — single operator, shutdown must be fully automatic with no manual intervention
- Automatic recovery — power return must bring everything back online without human action
- Single point of failure — one UPS protects everything; no redundancy to rely on, so the shutdown timer must be conservative enough to avoid unnecessary outages but aggressive enough to complete before battery exhaustion

## Considered Options

1. NUT on Proxmox hosts only (no NUT clients inside VMs)
2. NUT on Proxmox hosts + NUT clients on every NixOS VM
3. apcupsd on Proxmox hosts instead of NUT

## Decision Outcome

Chosen option: "NUT on Proxmox hosts only", because Proxmox already manages VM lifecycle via `qm shutdown` (ACPI), the existing `k3s-graceful-drain` systemd service fires on any clean shutdown regardless of trigger, and adding NUT clients inside VMs would duplicate the shutdown mechanism without meaningful benefit — adding a SOPS secret, a new NixOS module, and 4 host config changes for ~5 seconds of earlier drain start.

### Shutdown Cascade

```
T+0s    Power loss → UPS on battery
        → rohan detects OB via USB, upssched starts 5-min timer

T+15s   Prometheus scrapes nut_exporter → UPSOnBattery alert → ntfy phone notification

T+5m    upssched timer fires → rohan upsmon sends FSD to all NUT clients

        Proxmox hosts (the-shire, gondor) receive FSD:
        → shutdown-vms.sh: qm shutdown (ACPI to VMs) → 120s timeout → qm stop → host poweroff

        VMs receive ACPI from Proxmox:
        → systemctl poweroff
        → k3s-graceful-drain fires (ExecStop, cordon + drain, 60s timeout)
        → systemd shuts down VM

        rohan (master) shuts down last

T+??    UPS battery dies, or power returns to powered-off equipment
```

If power returns before the 5-min timer, upssched cancels and nothing shuts down. If LOWBATT (~20% battery) is reached before the timer fires, FSD triggers immediately as a safety net.

### Recovery

Proxmox BIOS "restore on AC power loss" powers on hosts → `on_boot = true` starts VMs → `k3s-auto-uncordon` waits for Ready and uncordons each node → cluster healthy.

### Consequences

- Good: Fully automatic shutdown and recovery — no manual intervention required at any step
- Good: Single shutdown mechanism per layer — Proxmox manages VMs, NUT manages Proxmox hosts. No duplication.
- Good: Existing `k3s-graceful-drain` and `k3s-auto-uncordon` scripts are shutdown-agnostic and require no changes
- Good: 5-minute timer rides out brief power blips while leaving ample battery for the shutdown cascade (~2-3 min for drain + poweroff)
- Bad: VMs have no direct UPS awareness — they rely on Proxmox sending ACPI shutdown. If Proxmox's ACPI delivery fails, VMs won't shut down gracefully.
- Bad: Once FSD fires, shutdown proceeds even if power returns (NUT does not cancel in-progress shutdowns)
- Neutral: All three k3s nodes drain simultaneously, so there's no healthy node to reschedule pods to during drain. This is expected — the entire cluster is going down.
- Neutral: Rohan is both the NUT server and a Proxmox host running the most critical VM (theoden). If rohan fails to detect the UPS or send FSD, the other hosts won't know to shut down.

### Infrastructure Assumptions

- **Network switch is on the UPS.** All three Proxmox hosts are on the same VLAN and share a managed switch. Since the switch has UPS-backed power, LAN connectivity between hosts is maintained during a power outage even though the router (default gateway) dies immediately. NUT's FSD propagation from rohan to gondor/the-shire relies on Layer-2 switch connectivity, not the router. **If the switch is ever moved off the UPS, this architecture breaks** — the slaves would lose network before receiving FSD, and would need independent shutdown logic (e.g., upssched on slaves with COMMBAD timer + gateway ping check).

- **Router is NOT on the UPS.** This is acceptable because NUT host-to-host communication does not traverse the router (same subnet). Router death only affects WAN/Internet access and DHCP lease renewal — neither of which matter during a shutdown cascade.

### Confirmation

This decision is working when: (1) unplugging UPS from wall triggers an ntfy phone notification within 30 seconds, (2) after 5 minutes on battery, all Proxmox hosts and VMs shut down cleanly with k3s drain completing successfully (check `journalctl -u k3s-graceful-drain` on each VM), (3) plugging UPS back in and waiting for Proxmox to boot results in all VMs running and k3s cluster healthy within 10 minutes, (4) plugging UPS back in within 5 minutes (before FSD) results in no shutdown and a "power restored" notification.

## Pros and Cons of the Options

### NUT on Proxmox hosts only

- Good: Simplest architecture — NUT runs on 3 Proxmox hosts (1 server + 2 clients), managed by existing Ansible `nut` role
- Good: No NixOS changes required — no new module, no SOPS secret, no host config modifications
- Good: Proxmox `shutdown-vms.sh` already handles graceful VM stop with timeout + force-kill fallback
- Good: Single shutdown path per VM — Proxmox ACPI → systemd poweroff → k3s drain. No race between two independent shutdown triggers.
- Good: Existing k3s-graceful-drain (60s timeout) and k3s-auto-uncordon services require zero changes
- Neutral: VMs start draining ~5-10 seconds later than they would with direct NUT FSD (time for Proxmox to process FSD, run shutdown-vms.sh, and send ACPI)
- Bad: No defense in depth — if Proxmox ACPI delivery is broken, VMs don't shut down gracefully
- Bad: VM-level UPS metrics (battery %, runtime) not available inside VMs (mitigated: nut_exporter on rohan exposes all UPS metrics to Prometheus)

### NUT on Proxmox hosts + NUT clients on every NixOS VM

- Good: VMs receive FSD directly from rohan, starting drain ~5-10 seconds earlier
- Good: Defense in depth — two independent shutdown mechanisms (NUT FSD + Proxmox ACPI)
- Good: `upsc` commands work inside VMs for local UPS status queries
- Good: If a VM is ever migrated to bare metal, NUT client travels with it
- Neutral: Two mechanisms both trying to shut down the same VM simultaneously — harmless in practice but conceptually messy
- Bad: New NixOS module (`modules/nixos/nut-client.nix`) to write and maintain
- Bad: New SOPS secret (`nut_upsmon_password`) to manage across 4 hosts
- Bad: 4 host configs to modify (boromir, samwise, theoden, rivendell) — rivendell excluded from UPS but would need the module available
- Bad: Race condition between NUT-initiated poweroff and Proxmox ACPI shutdown — both trigger k3s-graceful-drain independently, which could confuse `kubectl drain` if two shutdown signals arrive close together
- Bad: Marginal benefit — all 3 k8s nodes drain simultaneously regardless, so there's no healthy node to reschedule to. The 5-second head start doesn't improve outcomes.

### apcupsd on Proxmox hosts instead of NUT

- Good: Simpler configuration for single-UPS setups — apcupsd has fewer moving parts than NUT (no upsd/upsmon/upsdrvctl split)
- Good: Well-documented for APC UPS hardware
- Neutral: Could work with CyberPower via usbhid interface, but less commonly tested than NUT
- Bad: No native network monitoring — apcupsd's `net` mode is less flexible than NUT's client/server model for multi-host setups
- Bad: No equivalent to NUT's `upssched` for timer-based shutdown triggers — would require custom scripting for the 5-min timer
- Bad: Poorer Prometheus exporter ecosystem compared to NUT
- Bad: Less commonly used in Proxmox/NixOS communities — harder to find troubleshooting resources
