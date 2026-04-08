---
date: 2026-04-08
title: Tailscale TCP to erebor broken - nftables bypass table silently never loaded
severity: moderate
duration: Unknown (likely since April 7 fix was applied), 1h active debugging
systems: [tailscale, mullvad, nftables, openbao, terraform]
tags: [networking, vpn, nftables, tailscale, mullvad]
commit: https://codeberg.org/ananjiani/infra/commit/pending
---

## Summary

All TCP connections from ammars-pc to Tailscale peers (100.64.0.0/10) were rejected by Mullvad's firewall, despite a `networking.nftables.tables` bypass being configured. The bypass table was silently ignored because `networking.nftables.enable` was never set to `true`. This blocked terraform from reaching OpenBao on erebor, and would have affected any process not wrapped in `mullvad-exclude` that tried to reach a Tailscale peer.

## Timeline

All times CST.

- **~09:30** - While removing the pippin host, attempted to run `tofu plan` against OpenBao at `http://100.64.0.21:8200`. Connection refused.
- **~09:35** - Confirmed OpenBao is running on erebor (via SSH to public IP `91.99.82.115`). Service is healthy, bound to `0.0.0.0:8200`.
- **~09:38** - `tailscale ping erebor` succeeds (145ms via DERP, then direct at `91.99.82.115:41641`). `tailscale status` shows both peers as active with direct connection.
- **~09:40** - `curl http://100.64.0.21:8200` returns "Connection refused" in **0ms** — suspiciously fast for a remote connection.
- **~09:42** - SSH to erebor's Tailscale IP also refused. Checked `ss -tlnp` — both sshd and OpenBao bound to `0.0.0.0`. Checked `ts-input` iptables — correctly accepts tailscale0 traffic (533K packets).
- **~09:50** - Tested `tailscale nc erebor 8200` and `tailscale nc erebor 22` — both connect but return empty responses. SSH to the **public IP** works fine.
- **~09:55** - Tested every port on the Tailscale IP — all "Connection refused" instantly. Concluded the local machine is rejecting outbound, not the remote.
- **~10:00** - `mullvad-exclude curl http://100.64.0.21:8200` succeeds immediately. Confirmed Mullvad's firewall is the blocker.
- **~10:05** - Checked nftables bypass table. Initial theory: priority race (bypass at priority 0, same as Mullvad's filter). Changed to priority -10.
- **~10:10** - Rebuilt with `nh os switch`. Activation failed because vault-agent couldn't reach OpenBao (chicken-and-egg). Used `nixos-rebuild switch` to force through.
- **~10:15** - Still failing. Ran `sudo nft list table inet mullvad-tailscale-bypass` — **"No such file or directory"**. The table was never created.
- **~10:17** - Discovered `networking.nftables.tables` requires `networking.nftables.enable = true` to function. Without it, the table definition is silently discarded.
- **~10:20** - Replaced `networking.nftables.tables` with a systemd oneshot service that loads the table via `nft -f`. Kept the priority -10 fix.
- **~10:25** - Rebuilt and confirmed. `curl http://100.64.0.21:8200` returns OpenBao health JSON.

## What Happened

As part of decommissioning the pippin VM, terraform needed to run `tofu apply` to destroy infrastructure resources. Terraform's vault provider connects to OpenBao on erebor via its Tailscale IP (`100.64.0.21:8200`). The connection was immediately refused.

Initial investigation focused on the remote end — erebor's firewall, Tailscale daemon, and service binding. Everything looked correct: OpenBao was listening on all interfaces, iptables accepted tailscale0 traffic, and `tailscale ping` worked fine. The breakthrough was noticing the 0ms response time on "Connection refused" — a remote host can't respond that fast, so the rejection had to be local.

Testing with `mullvad-exclude curl` confirmed it: Mullvad's nftables output chain (policy `drop`) was rejecting all TCP to Tailscale CGNAT addresses. The `mullvad-tailscale-bypass` nftables table, configured in the April 7 triple-fault fix, was supposed to mark this traffic with `ct mark 0x00000f41` so Mullvad's filter would accept it. But the table never existed at runtime.

The `networking.nftables.tables` option in NixOS only takes effect when `networking.nftables.enable = true`, which switches the entire firewall backend from iptables-nft to native nftables. Enabling this would break Docker's iptables chains and Tailscale's `ts-input`/`ts-forward` chains. The fix was to load the table via a systemd oneshot service using `nft -f` directly, which coexists with the iptables-nft backend.

## Contributing Factors

- **Silent no-op**: `networking.nftables.tables` produces no warning when `networking.nftables.enable` is false. The config parses, evaluates, and builds successfully — it just doesn't do anything.
- **No runtime verification**: The April 7 fix was tested by restarting tailscaled (which worked because tailscaled itself is `mullvad-exclude`d), not by testing TCP from a non-excluded process.
- **Two firewall backends**: NixOS supports both iptables-nft and native nftables, but they don't compose freely. `networking.nftables.tables` belongs to the native backend only.
- **Priority race (secondary)**: Even if the table had been loaded, the output chain at priority 0 could race with Mullvad's filter chain at the same priority. Changed to -10 as a precaution.

## What I Was Wrong About

- **I assumed `networking.nftables.tables` was a standalone feature** that could add custom nftables tables regardless of the firewall backend. In reality, it's part of the native nftables backend and requires `networking.nftables.enable`.
- **I assumed the April 7 fix worked end-to-end**. It fixed the `ct mark` logic but was never actually loaded. Tailscale connectivity appeared to work because tailscaled itself runs under `mullvad-exclude`, and most Tailscale-dependent services (vault-agent, deploy-rs) run on the servers, not on the desktop.
- **I initially suspected the remote end**. The 0ms "Connection refused" should have immediately pointed to a local issue, but I spent 15 minutes checking erebor's firewall and service bindings first.

## What Helped

- **`mullvad-exclude curl`** was the decisive test — it immediately proved the issue was Mullvad's firewall, not Tailscale or the remote host.
- **The 0ms timing clue** — once noticed, it narrowed the problem to the local machine.
- **SSH access to erebor's public IP** provided a workaround for verifying the remote end was healthy.

## What Could Have Been Worse

- **If erebor only had a Tailscale IP** (no public IP), there would have been no way to verify or manage it remotely. The only fix path would have been Hetzner console access.
- **The bypass being silently ignored means any desktop process reaching Tailscale peers via TCP was broken** — not just terraform. If vault-agent on the desktop had been the only path to secrets, all secret-dependent services would have been down.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

NixOS options that silently no-op when a prerequisite isn't enabled are a footgun. This is the same class of issue as Nix flakes silently ignoring untracked files — the system accepts invalid config without complaint.

More broadly, the Mullvad/Tailscale integration on the desktop has required three separate fixes across two postmortems. The layering of Mullvad nftables, NixOS iptables-nft firewall, Tailscale's own iptables chains, and custom bypass rules is fragile. Each fix addresses one interaction but doesn't prevent the next.

## Action Items

- [x] Replace `networking.nftables.tables` with systemd oneshot service using `nft -f`
- [x] Change bypass output chain priority from 0 to -10 (before Mullvad's filter)
- [ ] Add a test script or activation check that verifies `nft list table inet mullvad-tailscale-bypass` succeeds after boot
- [ ] Document the Mullvad/Tailscale nftables layering in the repo (which chains exist, their priorities, and how they interact)

## Lessons

- **`networking.nftables.tables` requires `networking.nftables.enable`**. Without it, the tables are silently discarded. If you need custom nftables rules alongside the default iptables-nft backend, use a systemd service with `nft -f`.
- **"Connection refused" in 0ms means the local machine is rejecting** — no remote host can respond that fast. Always check local firewall rules first when you see instant rejections.
- **Test bypass rules from a non-excluded process**. `mullvad-exclude curl` is a quick way to verify whether Mullvad's firewall is the blocker.
- **NixOS's two firewall backends (iptables-nft vs native nftables) don't compose**. You can add standalone nftables tables via `nft -f`, but `networking.nftables.*` options only work with the native backend enabled.
