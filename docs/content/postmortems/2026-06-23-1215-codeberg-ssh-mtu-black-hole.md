---
date: 2026-06-23
title: Codeberg SSH failures from Mullvad PMTU black hole
severity: minor
duration: ~30m
systems: [desktop, mullvad, networking, ssh]
tags: [networking, mtu, pmtud, mullvad, wireguard, vpn]
commit: https://codeberg.org/ananjiani/infra/commit/103f5fd7
---

## Summary

`git pull` / `git push` over SSH to Codeberg failed with `Connection closed by 217.197.84.140 port 22` immediately after the server accepted the public key. The cause was a PMTU (Path MTU Discovery) black hole: traffic to Codeberg routes through the desktop's own `wg0-mullvad` tunnel (default MTU 1380), but the real path MTU past Mullvad's exit is ~1352 bytes. Large SSH signature packets exceeded it, were silently dropped, and the PMTUD ICMP replies never returned. Lowering the tunnel MTU to 1280 fixed it.

## Timeline

All times CST.

- **~12:05** - `git pull` failed with `Connection closed by 217.197.84.140 port 22`. Local staged WoL changes initially blocked the merge, so the SSH failure wasn't isolated until the pull was retried over HTTPS (which worked).
- **~12:08** - `ssh -vvv git@codeberg.org` showed: server accepts key (`receive packet: type 60`, "Server accepts key"), sends signature packet, then `Connection closed`. Not an auth rejection — connection dropped mid-handshake after the signature.
- **~12:09** - Reproduced 3/3 times with `BatchMode=yes`. Consistent, not flaky.
- **~12:10** - Binary PMTU probe: `ping -M do -s 1400` → `Message too long` (100% loss); `-s 1352` → success; `-s 1200` → success. Real path MTU sits between 1352 and 1400.
- **~12:11** - `ip route get 217.197.84.140` showed `dev wg0-mullvad` (desktop's own Mullvad tunnel, MTU 1380). Confirmed this is independent of the router's OPNsense Mullvad — not the same path.
- **~12:12** - Diagnosed: PMTU black hole. Mullvad default MTU 1380 > real path MTU ~1352, so signature packets (>1352B) vanish; ICMP "Fragmentation Needed" never returns.
- **~12:13** - Reviewed 4 prior MTU postmortems (flux HTTP/2 over VXLAN, forgejo registry, flannel VIP). Noted the 2026-03-02 lesson: don't *assume* MTU — must prove it. Binary ping test here proved it, not a misdiagnosis.
- **~12:14** - `mullvad tunnel set mtu 1280` applied manually. SSH to codeberg succeeded immediately.
- **~12:15** - Pushed both pending commits over SSH. Confirmed resolved.

## What Happened

The desktop runs Mullvad VPN as a WireGuard tunnel (`wg0-mullvad`), owned entirely by `mullvad-daemon` (not NixOS `networking.wireguard`). Mullvad's default tunnel MTU is 1380, which accounts for the 80 bytes of WireGuard encapsulation against a 1500-byte physical MTU. The math is "correct" for the tunnel itself.

The problem is what happens *past* the Mullvad exit. Traffic to Codeberg leaves the Mullvad endpoint and traverses additional encapsulation (MPLS, additional tunneling, or provider-internal overhead) that pushes the real end-to-end path MTU down to ~1352 bytes. Mullvad has no visibility into this — from its perspective the tunnel MTU is 1380 and that's what it sets on `wg0-mullvad`.

For most traffic this is invisible: small packets (DNS, HTTP GET, TLS ClientHello) all fit under 1352 bytes. SSH's key exchange is the exception — the public-key signature packet that the client sends after the server accepts the key exceeds 1352 bytes, sets the Don't Fragment flag (standard for TCP), and gets silently dropped somewhere past the Mullvad exit. The kernel should receive an ICMP "Fragmentation Needed" reply (PMTUD) and lower its effective MSS, but that ICMP either never gets generated, gets filtered, or can't traverse the reverse path. The sender never learns the packet is too big, so it re-sends the same oversized signature, which drops again, until SSH times out or the server closes the connection after the handshake stalls.

The HTTPS pull earlier in the session worked because TCP over HTTPS negotiates a smaller MSS during the handshake (TCP options fit under the MTU), so the connection stays within the viable packet size. SSH's handshake structure — where the oversized payload comes *after* the TCP handshake completes — is exactly the pattern that defeats a PMTU black hole.

## Contributing Factors

- **Mullvad's default MTU (1380) only accounts for its own encapsulation.** It can't see additional overhead past the exit node (MPLS labels, downstream tunnels, provider path MTU shrinkage). The value is correct for the tunnel, wrong for the path.
- **PMTUD is end-to-end and assumes ICMP works.** The "Fragmentation Needed" reply must traverse the entire reverse path back to the sender. Any device filtering ICMP, any asymmetric route, or any further encapsulation breaking the ICMP payload drops it silently. The sender then has no way to learn the constraint.
- **SSH's handshake has a large mid-exchange packet.** The signature packet is one of the largest single payloads in the SSH handshake and lands after the TCP handshake, so TCP MSS negotiation can't pre-shrink it.
- **DF (Don't Fragment) is default-on for TCP.** No kernel-level fallback to fragmentation once the oversized packet is built.
- **Mullvad-daemon owns `wg0-mullvad`.** Can't set the MTU via NixOS `networking.wireguard`; must go through `mullvad tunnel set mtu`. This is an interface-control constraint, not a bug, but it shapes the fix.

## What I Was Wrong About

- **Initially treated it as "Codeberg SSH auth problem."** The `Connection closed` right after `Server accepts key` *looks* like an auth failure on a quick read of the SSH log. It isn't — the server accepted the key, asked for the signature, and dropped the connection when the signature packet never arrived. The drop happened on the wire, not at the server's auth logic.
- **First instinct was to reach for a codeberg-specific bypass** (nft rule, like the existing tailscale-bypass). Wrong framing — this isn't Codeberg's fault and isn't specific to one destination. Any host past the Mullvad exit with a path MTU < 1380 would exhibit the same symptom; Codeberg was just the first one that did a large handshake.

## What Helped

- **The binary `ping -M do -s <size>` probe.** The single most decisive test. `-s 1400` failed, `-s 1352` worked. That's a measured path-MTU boundary, not a guess. This is what distinguishes a real MTU diagnosis from the misdiagnosis called out in the 2026-03-02 flannel postmortem (where MTU was assumed but the real cause was corrupted routes).
- **`ssh -vvv` packet-type trace.** `receive packet: type 60` (server accepts key) followed by `Connection closed` immediately after `sign_and_send_pubkey` pinpoints where in the handshake the packet was lost. Without the verbose log this looks like a generic auth failure.
- **`ip route get <dest>`.** One command confirmed the path goes through `wg0-mullvad` and *not* the router's OPNsense Mullvad. This immediately scoped the fix to the desktop and ruled out touching the router.
- **Prior postmortems.** The MTU pattern was already documented four times. Knowing the symptoms and the "prove it with ping, don't assume" lesson (from 2026-03-02) cut the investigation to minutes.

## What Could Have Been Worse

- **If the symptom had been intermittent rather than consistent**, it would have been far harder to pin down. 3/3 `BatchMode=yes` failures is easy to reproduce; a 1-in-10 flake would have pointed at network instability instead of a hard PMTU boundary.
- **If only large git operations failed** (e.g. cloning a big repo) while small SSH commands worked, the SSH handshake signature would have been the wrong size class to trigger it and the diagnosis would have looked like "git over SSH is slow/broken" rather than "the tunnel MTU is wrong." The handshake is the canary precisely because it's a large single packet.
- **If the HTTPS fallback hadn't worked**, the merge conflict + SSH failure would have been a single blocking wedge with no easy workaround to unblock the pull while debugging.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This is the **fifth** MTU-related incident documented here (after forgejo registry push, flux HTTP/2 over VXLAN, flannel VIP route corruption's MTU tangent, and the underlying flannel cni0 MTU work). The recurring thread across all of them: **tunnel/overlay MTU is set to the encapsulation-theoretic minimum with no headroom, and some downstream path or protocol overhead then exceeds it.**

The systemic fix is the one this incident lands on: set tunnel MTUs with deliberate headroom, not to the exact encapsulation math. 1280 (the IPv6 minimum, also what Tailscale uses) leaves ~100 bytes of margin inside the WireGuard encapsulation and matches what the February flux postmortem advocated for Flannel VXLAN. The general rule: **a tunnel's MTU should assume the path past its own egress is lossy on ICMP, and budget accordingly.**

## Action Items

- [x] Lower `wg0-mullvad` MTU to 1280 via `mullvad tunnel set mtu` manually (immediate fix, verified working)
- [x] Add `mullvad-mtu` systemd service in `modules/nixos/privacy.nix` to persist 1280 across reboots (`103f5fd7`). Applies to both workstations via the workstation profile.
- [ ] Verify on `framework13` after its next rebuild — same Mullvad setup, should benefit from the same fix.
- [ ] Consider whether the router's OPNsense Mullvad client has the same default MTU and whether it needs the same treatment (separate path, not part of this incident, but same class of bug).

## Lessons

- **`Connection closed` right after `Server accepts key` is a PMTU symptom, not an auth symptom.** The server accepted the key and asked for the signature; the signature packet was too big for the path and vanished. Read the SSH `-vvv` packet-type sequence, not just the final error line.
- **Prove MTU with `ping -M do -s <size>`, don't assume it.** The 2026-03-02 flannel postmortem got burned by assuming MTU when the real cause was route corruption. A binary search on packet size (1400 fails / 1352 works) is the proof.
- **`ip route get <dest>` first.** One command tells you which interface and therefore which tunnel the traffic traverses. This scoped the fix to the desktop and ruled out the router's VPN in seconds.
- **Tunnel MTU defaults assume ICMP works end-to-end.** It doesn't, past any commercial VPN exit. Budget headroom, don't trust the encapsulation-theoretic minimum.
- **SSH handshake is the canary for PMTU black holes** because it's one of the largest single-packet payloads a TCP connection sends, and it lands after MSS negotiation so TCP can't pre-shrink it. "SSH works but HTTPS works" (or vice versa) is a MTU signal.
