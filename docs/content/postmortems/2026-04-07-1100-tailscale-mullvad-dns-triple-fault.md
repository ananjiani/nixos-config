---
date: 2026-04-07
title: Tailscale connectivity failure from desktop - dynamic IP, DNS routing, and firewall triple fault
severity: moderate
duration: 12h+ (broken since boot), 1h active debugging
systems: [tailscale, mullvad, adguard, cloudflare, opnsense, nftables]
tags: [networking, vpn, dns, tailscale, mullvad]
commit: https://codeberg.org/ananjiani/infra/commit/pending
---

## Summary

Tailscale on the desktop (ammars-pc) was unable to connect to the Headscale control server, leaving it in `NoState` since boot. Three independent issues combined: a stale WAN IP in DNS, Mullvad capturing DNS queries away from AdGuard's split-DNS rewrite, and an incomplete nftables bypass rule that prevented regular processes from reaching Tailscale IPs.

## Timeline

All times CST.

- **~08:51** - Desktop boots. `tailscaled-autoconnect` times out after 90s because tailscaled can't reach `ts.dimensiondoor.xyz`
- **~08:51** - `mullvad-exclude` logs "No net_cls controller found" on first attempt (PID 1644), but tailscaled starts successfully on retry (PID 1860) in the `mullvad-exclusions` cgroup
- **08:51–10:30** - tailscaled retries every ~30s, always failing with `dial tcp 72.182.230.42:443: connect: no route to host`
- **~10:35** - Investigation begins. `tailscale status` shows peers from stale state but health check reports "logged out"
- **~10:37** - Discovered `72.182.230.42` is the old WAN IP. Actual WAN IP is `70.119.78.245` (ISP changed it)
- **~10:39** - Updated `homeserver_ip` in Terraform, ran `tofu apply` to update Cloudflare DNS records
- **~10:41** - DNS propagated but tailscaled still fails — now `dial tcp 70.119.78.245:443: connect: connection timed out` (NAT hairpin failure)
- **~10:43** - Confirmed NAT hairpin doesn't work on OPNsense even after enabling reflection settings
- **~10:45** - Discovered AdGuard already has a DNS rewrite (`ts.dimensiondoor.xyz → 192.168.1.52`) but `resolvectl query` returns the Cloudflare answer via `link: wg0-mullvad`
- **~10:46** - Found that Mullvad sets `DNS Domain: ~.` on wg0-mullvad, capturing all DNS queries to its own resolver (`10.64.0.1`), bypassing AdGuard
- **~10:47** - Ran `mullvad dns set custom 192.168.1.53 192.168.1.1` to route Mullvad DNS through AdGuard. `resolvectl query` now returns `192.168.1.52` via `link: eno1`
- **~10:47** - Restarted tailscaled. Control server key fetched successfully, `ipn state → Running`
- **~10:48** - `tailscale ping 100.64.0.1` works (boromir). But `ping 100.64.0.21` (erebor) fails — regular ICMP doesn't traverse the Tailscale interface
- **~10:50** - Confirmed `mullvad-exclude ping 100.64.0.21` works but regular `ping` doesn't — Mullvad's firewall blocks non-excluded traffic to Tailscale IPs
- **~10:52** - Found that the existing nftables bypass rule only sets `meta mark 0x6d6f6c65` (routing bypass) but is missing `ct mark 0x00000f41` (Mullvad's split-tunnel connection tracking mark)
- **~10:55** - Applied updated nftables rules with both marks plus an input chain for return traffic
- **~10:55** - Regular `ping 100.64.0.21` works. `curl http://100.64.0.21:8282/mcp` works. Full connectivity restored

## What Happened

Tailscale on the desktop has a complex relationship with Mullvad VPN. Tailscaled is wrapped in `mullvad-exclude` so it can operate outside the VPN tunnel, while regular traffic goes through Mullvad. An nftables rule marks Tailscale-destined traffic (100.64.0.0/10) to bypass Mullvad's routing table.

This setup was working but broke when three things collided:

**First**, the ISP assigned a new WAN IP (`70.119.78.245`, previously `72.182.230.42`). The Cloudflare DNS record for `ts.dimensiondoor.xyz` still pointed to the old IP. Since this record is unproxied (required for Tailscale), clients couldn't reach Headscale at all.

**Second**, even after fixing DNS, tailscaled couldn't connect because it resolved `ts.dimensiondoor.xyz` through Mullvad's DNS (`10.64.0.1`) rather than AdGuard (`192.168.1.53`). AdGuard has a split-DNS rewrite that returns the internal Traefik VIP (`192.168.1.52`), but Mullvad's `~.` DNS domain on the wg0-mullvad interface captures all queries before they reach AdGuard. The `mullvad dns set custom` command had been manually disabled during earlier testing and wasn't active.

**Third**, even with tailscaled connected, regular processes couldn't reach Tailscale IPs. The nftables bypass rule set `meta mark 0x6d6f6c65` for routing, but Mullvad's firewall also checks `ct mark` (connection tracking mark). Without `ct mark 0x00000f41` (Mullvad's split-tunnel classid), Mullvad's nftables chains dropped the packets regardless of routing.

## Contributing Factors

- **Dynamic WAN IP with no DDNS**: ISP changed the IP with no automatic update mechanism for Cloudflare DNS
- **Mullvad DNS domain `~.` captures all queries**: systemd-resolved routes all DNS through Mullvad when custom DNS is not set, bypassing local AdGuard
- **Manual Mullvad DNS override was disabled**: The `mullvad dns set custom` had been turned off during earlier testing, and the systemd service didn't detect this
- **Incomplete nftables bypass**: The original rule only handled routing (`meta mark`) but not Mullvad's firewall (`ct mark`)
- **NAT hairpin not working on OPNsense**: Even with reflection enabled, traffic from LAN to WAN IP didn't reflect back — making the split-DNS path the only viable approach
- **No monitoring for Tailscale health**: The `tailscaled-autoconnect` timeout at boot was the only signal, and it's a oneshot that doesn't retry

## What I Was Wrong About

- **Assumed the WAN IP was static enough**: It hadn't changed in a while, so the stale `homeserver_ip` in Terraform wasn't noticed. Dynamic IPs from residential ISPs can change at any reboot or DHCP lease renewal
- **Assumed AdGuard's DNS rewrite was being used**: The rewrite existed but Mullvad's DNS routing meant it was never queried. `resolvectl status` showed the `~.` domain routing but this wasn't checked until the incident
- **Assumed `meta mark` was sufficient for Mullvad bypass**: Mullvad uses both routing policy (fwmark) and firewall rules (ct mark / cgroup). The routing bypass alone isn't enough — packets that pass routing still get dropped by Mullvad's nftables filter chains
- **Assumed NAT hairpin would work on OPNsense**: Enabled the settings but it still didn't work, possibly because the port forward rules aren't configured for reflection or OPNsense needs additional setup

## What Helped

- **AdGuard already had the split-DNS rewrite**: `ts.dimensiondoor.xyz → 192.168.1.52` was already configured, just not being queried
- **`mullvad-exclude` as a debugging tool**: Testing with `mullvad-exclude curl/ping` vs regular `curl/ping` isolated whether Mullvad was the culprit at each stage
- **`resolvectl query` shows the link**: The `-- link: wg0-mullvad` output immediately revealed DNS was going through the wrong path
- **Tailscale's stale peer state**: Even though tailscaled couldn't reach the control server, it retained peer info from previous sessions, so `tailscale status` still showed the peer list for context
- **TheOrangeOne's blog post**: Documented the exact `ct mark 0x00000f41` needed for Mullvad's split-tunnel bypass

## What Could Have Been Worse

- **If Headscale ran outside the LAN** (e.g., on erebor), the split-DNS approach wouldn't work — the only fix would be DDNS or a static IP
- **If all servers depended on Tailscale for management**: SSH via public IP (erebor) was still available as a fallback. If Tailscale had been the only management path, this outage would have been much harder to recover from
- **If the Mullvad custom DNS service had a real bug**: The manual disable was the cause, but if the systemd oneshot had a race condition, it could silently fail on every boot

## Is This a Pattern?

- [x] Pattern: Revisit the approach

This is the intersection of three systemic issues:

1. **Dynamic IP without DDNS** — will happen again on the next IP change
2. **Mullvad DNS capture** — any time Mullvad custom DNS is unset (manually or by bug), all split-DNS rewrites break
3. **Incomplete VPN bypass rules** — the nftables fix is now correct, but the original rule was written without understanding Mullvad's dual-mark system

## Action Items

- [x] Update `homeserver_ip` to current WAN IP in Terraform
- [x] Fix nftables bypass: add `ct mark 0x00000f41` and input chain for return traffic
- [x] Update `.mcp.json` and Terraform `openbao_address` to use Tailscale IP directly (no SSH tunnels)
- [x] Set Mullvad custom DNS back to AdGuard
- [ ] Set up DDNS to auto-update Cloudflare DNS on WAN IP change (Codeberg issue #77)
- [ ] Add Tailscale health check to monitoring (alert if control server unreachable)
- [ ] Document the Mullvad+Tailscale nftables interaction in the repo (the `ct mark` requirement is non-obvious)

## Lessons

- **Dynamic IPs break unproxied DNS records silently**: `ts.dimensiondoor.xyz` was the only unproxied record that mattered, and it was the one that broke. DDNS is essential for residential connections
- **`resolvectl query` shows the DNS path, not just the answer**: The `-- link:` field reveals which interface's DNS server answered. This is critical when multiple DNS paths exist (Mullvad, systemd-resolved, AdGuard)
- **Mullvad's firewall uses `ct mark`, not just routing marks**: To bypass Mullvad for specific traffic, you need both `ct mark set 0x00000f41` (firewall bypass) and `meta mark set 0x6d6f6c65` (routing bypass). The `0x0f41` value is Mullvad's split-tunnel cgroup classid
- **Test with AND without `mullvad-exclude`**: If something works with `mullvad-exclude` but not without, the issue is in Mullvad's firewall, not in routing
- **Three independent failures look like one big mystery**: Each issue alone would have been straightforward. The combination made it seem like a single complex problem, but decomposing into DNS resolution → DNS routing → packet filtering made each step solvable
