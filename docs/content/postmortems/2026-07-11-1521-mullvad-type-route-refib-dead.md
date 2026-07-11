---
date: 2026-07-11
title: Mullvad type-route re-fib dead on kernel 6.18 — Tailscale/OpenBao blackhole
severity: moderate
duration: recurring; ~2h investigation on 2026-07-11
systems: [mullvad, tailscale, openbao, direnv, desktop]
tags: [networking, mullvad, tailscale, nftables, kernel]
commit: https://codeberg.org/ananjiani/infra/commit/9189ae71
related:
  - 2026-04-07-1100-tailscale-mullvad-dns-triple-fault.md
  - 2026-04-08-1300-tailscale-nftables-bypass-never-loaded.md
  - 2026-04-10-1315-mullvad-dns-dry-regression.md
---

## Summary

On ammars-pc, Tailscale data-plane connectivity (and therefore OpenBao at
`100.64.0.21:8200`) was blackholed whenever Mullvad was connected. Direnv
appeared to hang because the devshell `shellHook` called `bao kv get` on every
load. Root mechanism: nftables `type route` chains set the right marks
(counters fire) but **do not re-fib on kernel 6.18.35**, so packets keep the
tunnel source IP and get dropped by Mullvad's
`oif wg0-mullvad ct mark 0xf41 drop` NAT rule. Fixed by abandoning type-route
re-fib entirely: policy `ip rule` entries ahead of Mullvad's rule 5209, plus an
nft **filter** ct-mark fixup.

## Timeline

All times CDT (UTC-5), 2026-07-11.

- **~13:50** - Noticed `direnv: ... is taking a while` on every `cd` into the
  repo. Message said "Using cached dev shell" so evaluation was not the issue.
- **~13:55** - Traced `.envrc` → flake `shellHook` → two `bao kv get` calls to
  OpenBao over Tailscale. `timeout 5 bao` exit 124.
- **~14:00** - Moved B2 creds out of shellHook into `scripts/tofu` wrapper
  (committed `c9b9a263`) so direnv no longer blocks on network. Underlying
  OpenBao unreachability remained.
- **~14:05** - `tailscale status`: self offline / one-way; `mullvad-exclude curl`
  to WAN timed out; LAN via exclude worked. Mullvad DNS was already correct
  (custom LAN resolvers). Bypass oneshot unit had been active since boot
  (Fri 09:51).
- **~14:10** - Confirmed tailscaled is in `net_cls:/mullvad-exclusions` with
  classid `5087041`, and Mullvad's mangle rule
  `meta cgroup 5087041 ct mark set 0xf41 meta mark set 0x6d6f6c65` was present.
- **~14:15** - `ss` on excluded connect to 1.1.1.1 showed
  `src 10.165.62.156` (tunnel IP) and cgroupv2 path
  `system.slice/tailscaled.service` — mark path not taking effect for routing.
- **~14:20** - Live-tested `socket cgroupv2` match + existing dest-based
  `100.64.0.0/10` type-route rules. **Counters incremented; source IP stayed
  tunnel.** type-route re-fib confirmed dead.
- **~14:25** - Same failure with `table ip` (not inet) and with iptables
  `MARK`/`CONNMARK` in mangle OUTPUT. Marks apply; route does not change.
- **~15:00** - `SO_MARK` set **before** `connect()` (CAP_NET_ADMIN):
  - mole mark → `100.64.0.21` binds `100.64.0.4` (correct)
  - mole mark → `1.1.1.1` binds `192.168.1.50` (correct) but TCP refused
    (Mullvad filter missing ct mark 0xf41)
  - Proved policy routing works when mark is present at first fib lookup;
    re-fib after output mangle does not.
- **~15:05** - Installed `ip rule` 5190–5202 (mole + Tailscale SO_MARK
  `0x80000/0xff0000`) ahead of Mullvad's 5209, plus nft **filter** ct-mark
  fixup. `tailscale ping erebor` → pong direct `91.99.82.115:41641`.
- **~15:10** - Added rule 5180 `to 100.64.0.0/10 lookup 52` so unmarked local
  processes (curl, bao) also reach CGNAT. OpenBao `/v1/sys/health` returned
  healthy JSON.
- **~15:20** - Durable form written into
  `hosts/desktop/configuration.nix` (`mullvad-tailscale-bypass` service +
  re-apply on `mullvad-daemon` restart). Live apply script confirmed.

## What Happened

Direnv slowdown looked like a Nix/cache problem ("using cached dev shell" but
still hanging). The real cost was in `shellHook`: two OpenBao fetches that
blocked until TCP connect timeout whenever Tailscale could not reach erebor.

Tailscale looked "half up": control plane sometimes online, data plane dead.
That pattern has appeared before on this host (April 7/8/10 postmortems) and
the prior fix was an nftables type-route chain that sets Mullvad's split-tunnel
marks (`ct mark 0xf41`, `meta mark 0x6d6f6c65`) for CGNAT destinations and for
excluded cgroups.

On today's kernel, every variant of that approach **matched packets** (nft
counters and iptables counters both non-zero) but left the socket bound to the
Mullvad tunnel address. Once the ct mark was set while oif was still
`wg0-mullvad`, Mullvad's NAT rule dropped the packet — a designed safety
property that becomes a blackhole when re-fib fails.

Mullvad's own split-tunnel path is the same mechanism (`type route` +
`meta cgroup`), so `mullvad-exclude` for WAN was equally dead. LAN still worked
because rule `5208 lookup main suppress_prefixlength 0` serves on-link routes
without needing the mole mark.

The fix that worked does not ask the kernel to re-route after mangle:

1. **ip rules before 5209** so traffic that already carries Tailscale's
   `SO_MARK 0x80000` (or the mole mark) never enters the tunnel table.
2. **ip rule for `to 100.64.0.0/10 lookup 52`** so unmarked processes reach
   peers without any mark.
3. **nft filter (priority -10)** only sets `ct mark 0xf41` so Mullvad's
   firewall accepts the already-correctly-routed packets.

## Contributing Factors

- **Kernel 6.18.35 type-route re-fib no-op** — nft/iptables marks apply on
  OUTPUT, counters prove match, `ip route get ... mark` shows the desired
  path, but locally generated sockets keep the pre-mangle route/source.
- **Mullvad rule 5209** (`not fwmark mole → tunnel table`) is totalizing: any
  failure of the mark/re-fib path sends *all* non-mole traffic into the tunnel,
  including Tailscale's own marked packets and CGNAT destinations.
- **Blackhole composition** — mark applied without re-fib +
  `oif wg0 ct mark 0xf41 drop` = silent drop, not a visible reject.
- **Dual-VPN stack on the desktop** — fourth incident in this cluster (April
  7 triple-fault, April 8 bypass never loaded, April 10 DNS dry, today
  re-fib). Each fix assumed type-route re-fib works.
- **shellHook network I/O on every direnv load** — turned a connectivity
  failure into a constant UX hang, with errors swallowed by
  `2>/dev/null || true`.
- **No runtime probe** that "excluded WAN works" or "bao over tailnet
  works" — failure only noticed when something interactive blocked.

## What I Was Wrong About

- **"If the nft rule counter ticks, routing changed."** Counters only prove
  the expression matched. On this kernel, type-route does not re-fib; the
  only reliable proof is `ss` source address or `SO_MARK` before connect.
- **"Mullvad-exclude is the ground truth for 'outside the tunnel'."** When
  Mullvad's own mangle re-fib is dead, exclude is also dead for WAN. LAN
  success via exclude was a false signal (suppress_prefixlength path).
- **"Dest-based 100.64 marks are enough for Tailscale."** They only help
  *inner* packets to peers, and only if re-fib works. Tailscaled's *outer*
  DERP/WG packets are public destinations and need the SO_MARK policy path.
- **"Restarting mullvad-daemon / tailscaled will heal split-tunnel."** The
  rules were present and matching after restart; the kernel behavior was the
  bug. Restarts wasted time.
- **"direnv hang ⇒ flake/eval problem."** Cached shell + hang almost always
  means shellHook or env work, not evaluation.

## What Helped

- `timeout 5 bao` immediately separated "slow" from "blackholed."
- `ss -tnp` source IP was the decisive signal (tunnel vs LAN vs tailscale0).
- `ip route get ... mark 0x6d6f6c65` proved policy routing tables were correct
  once the mark was present at lookup time.
- `SO_MARK` before `connect()` isolated re-fib failure from fib content.
- Prior postmortems documented both required marks and the NAT drop rule, so
  we did not have to rediscover Mullvad's mark constants.
- Probe scripts with counters (`/tmp/probe-bypass*.sh`) made "matched but
  didn't re-route" undeniable in one screen of output.

## What Could Have Been Worse

- Deploy-rs / vault-agent on servers do not depend on the desktop tailnet path
  for their own operation; only workstation→lab tools (bao, tofu state, some
  kubectl paths) were hit. A desktop-as-jump-host workflow would have been a
  full outage.
- If OpenBao had been sealed or unreachable on the server side for real, the
  same symptoms would have been mis-attributed again to desktop networking.
- `shellHook` swallowing bao errors meant empty `AWS_*` for tofu rather than a
  hard failure — silent credential absence on top of the hang.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

This is the **fourth** Mullvad×Tailscale postmortem on ammars-pc in ~3 months.
Previous fixes all layered more type-route / cgroup / DNS assumptions onto the
same dual-VPN design. Today's failure is not a misconfiguration of those
layers — it is the kernel not honoring the mechanism the whole stack depends
on.

The April 10 postmortem already opened an ADR item: evaluate removing the
dual-VPN stack (Mullvad on gateway only, Tailscale exit nodes, netns, or drop
Mullvad on desktop). That ADR is still outstanding and is now higher priority.

Until then, the policy-rule approach is the supported bypass on this host;
do not reintroduce type-route mark-and-re-fib as the primary mechanism.

## Action Items

- [x] Lazy-fetch B2 creds via `scripts/tofu` (done: `c9b9a263`) — direnv no
      longer blocks on OpenBao
- [x] Live policy-rule + ct-mark fixup applied on ammars-pc
- [ ] `nh os switch` to persist `mullvad-tailscale-bypass` from
      `hosts/desktop/configuration.nix`
- [ ] Commit the desktop config change and link this postmortem
- [ ] Add a tiny smoke check (systemd timer or script):
      `curl -sf --connect-timeout 3 http://100.64.0.21:8200/v1/sys/health`
      and alert/log on failure — catches this class without waiting for direnv
- [ ] Write the dual-VPN ADR deferred from 2026-04-10 (options: Mullvad on
      gateway only, Tailscale exit nodes for "VPN", netns isolation, keep
      current with policy-rule guardrails only)
- [ ] File or track upstream: nftables/kernel type-route re-fib no-op on
      6.18 when multiple `type route` OUTPUT chains exist (iptables-nft
      mangle + Mullvad inet mangle + custom tables)
- [ ] Revisit Edge resume workaround after ADR — still a separate kill-switch
      window issue, not fixed by this change

## Lessons

- **Prove routing with source address, not rule counters.**
  `ss`/`SO_MARK`/`ip route get mark` > nft counter.
- **type route re-fib is not a reliable primitive on this desktop kernel.**
  Prefer ip rules that match marks already set in userspace (Tailscale
  SO_MARK) or pure destination rules.
- **Mullvad 5209 is a single point of failure for anything that is not mole-marked.**
  Anything that must leave via LAN or tailscale0 needs an earlier ip rule.
- **shellHook must not do unbounded network I/O.** Lazy wrappers, timeouts, or
  both.
- **Recurring dual-VPN incidents are an architecture signal**, not a series of
  unrelated firefights. Stop adding epicycles without the ADR.
- **Next time direnv hangs with a cached shell:** check shellHook and any
  external calls first, not flake evaluation.
