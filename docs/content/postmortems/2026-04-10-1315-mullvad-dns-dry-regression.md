---
date: 2026-04-10
title: Mullvad DNS regression — DRY refactor reintroduced the April 7 triple-fault
severity: moderate
duration: ~2 days latent (since 2026-04-08 17:44 CST), ~45min active debugging
systems: [tailscale, mullvad, nixos, adguard, openbao, claude-code]
tags: [networking, vpn, dns, tailscale, mullvad, regression]
commit: https://codeberg.org/ananjiani/infra/commit/pending
---

## Summary

Tailscale on ammars-pc silently stopped working at the next reboot after a cosmetic DNS refactor (commit `4bd9a5d`, 2026-04-08 17:44 CST). The refactor centralized nameservers into `base.nix` and added Quad9 as a public fallback — which quietly poisoned Mullvad's custom DNS list. Mullvad filtered the LAN resolvers out when publishing to `wg0-mullvad`, leaving only Quad9, which bypassed AdGuard's split-DNS rewrite for `ts.dimensiondoor.xyz`. Tailscaled couldn't fetch its control key and stayed logged out, making the vault MCP (on erebor, only reachable via Tailscale at `100.64.0.21`) unreachable from Claude Code.

This is a direct regression of the 2026-04-07 triple-fault postmortem. The manual fix from that incident (`mullvad dns set custom 192.168.1.53 192.168.1.1`) had been made declarative in the meantime, but the declarative version silently included a public fallback.

## Timeline

All times CST.

- **2026-04-07 ~10:47** - Original triple-fault fix: `mullvad dns set custom 192.168.1.53 192.168.1.1` (two servers, LAN-only). Tailscale working.
- **2026-04-08 17:44** - Commit `4bd9a5d` "refactor(dns): centralize nameservers in base.nix via lib/dns.nix" adds `lib/dns.nix` with three servers including `9.9.9.9`. Commit message explicitly notes "Added Quad9 as public fallback". `privacy.mullvadCustomDns` already referenced `dns.servers`, so the next `nh os switch` silently re-ran `mullvad dns set custom 192.168.1.53 192.168.1.1 9.9.9.9`. **Regression introduced at this moment.**
- **2026-04-08 17:47** - Commit `0088fe4` "refactor(dns): delete lib/dns.nix, inline nameservers in base.nix" replaces `dns.servers` with `config.networking.nameservers`. Behavior-identical to the previous commit — both contain Quad9.
- **2026-04-08 → 2026-04-10** - Latent period. tailscaled held a pre-regression control session, so Tailscale kept working across rebuilds. No visible symptom.
- **2026-04-10 ~08:51** - Desktop boot. tailscaled starts fresh and needs to re-auth. `dial tcp 70.119.78.245:443: connect: connection timed out` on every retry (journal shows this starting immediately after boot). Tailscale stays in `NoState`.
- **2026-04-10 ~12:15** - Claude Code displays `/mcp` → "Failed to reconnect to vault".
- **~12:30** - Investigation begins. `tailscale status` shows `NoState` + "logged out" + control key fetch timing out.
- **~12:33** - Confirmed `curl https://ts.dimensiondoor.xyz/health` works from a normal process (returns `{"status":"pass"}`), but tailscaled (running under `mullvad-exclude`) cannot reach the same URL. Suspected April 8 nftables bypass regression.
- **~12:36** - `systemctl is-active mullvad-tailscale-bypass` → `active`; `sudo nft list table inet mullvad-tailscale-bypass` (later) confirmed the table is loaded. April 8 fix is intact.
- **~12:38** - `mullvad dns get` shows `192.168.1.53, 192.168.1.1, 9.9.9.9`. `dig @192.168.1.53 ts.dimensiondoor.xyz` returns `192.168.1.52` (AdGuard's rewrite works). `resolvectl query ts.dimensiondoor.xyz` returns `70.119.78.245 -- link: wg0-mullvad`. Something is routing queries away from AdGuard.
- **~12:42** - `resolvectl` dump shows `wg0-mullvad` has only `9.9.9.9` as its DNS server, despite `mullvad dns get` listing three. Concluded Mullvad filters LAN servers out when publishing to the tunnel link because LAN IPs aren't routable via `wg0-mullvad`.
- **~12:50** - `grep` for `9.9.9.9` in the repo. Found it in `hosts/_profiles/base.nix:125` and traced `privacy.mullvadCustomDns = config.networking.nameservers` in `hosts/desktop/configuration.nix:41`. Root cause identified.
- **~12:55** - `git log -S "mullvadCustomDns"` and `git log -S "9.9.9.9" -- lib/dns.nix` traced the regression to commit `4bd9a5d` on 2026-04-08 17:44. The bug has been latent for ~2 days.
- **~13:05** - Edited `hosts/desktop/configuration.nix:41` to hardcode `[192.168.1.53, 192.168.1.1]` (LAN-only), removed now-unused `config` function argument, added a block comment explaining why this list must not be DRY'd with `networking.nameservers`.
- **~13:10** - `nh os switch` applied. `mullvad-custom-dns` oneshot re-ran and set Mullvad DNS to the two-element list.
- **~13:12** - Verification: `mullvad dns get` shows 2 servers; `resolvectl query ts.dimensiondoor.xyz` returns `192.168.1.52 -- link: eno1`; `tailscale status` shows `erebor active; direct 91.99.82.115:41641`; `curl http://100.64.0.21:8282/mcp` returns `HTTP/1.1 200 OK` with `Content-Type: text/event-stream` (MCP handshake).
- **~13:15** - Postmortem written.

## What Happened

Two days before the visible outage, I did a cleanup refactor to centralize DNS configuration: `networking.nameservers` was scattered across multiple host files, and I wanted a single source of truth in `base.nix`. At the same time, I added Quad9 as a public fallback, which seemed like pure upside — if AdGuard and the router both became unreachable, the host would still resolve. The commit message literally says "Added Quad9 as public fallback" in a positive tone. I did not think about Mullvad at all during this refactor — the refactor was about NixOS nameserver consistency, and `privacy.mullvadCustomDns` just happened to be another consumer of the same list.

The reason the refactor didn't immediately break anything is subtle: `tailscaled` on ammars-pc had an active control session from before the refactor. Once a Tailscale node has logged in, it keeps a node key valid for weeks without re-contacting the control server. So Tailscale kept working across `nh os switch` rebuilds, across the `mullvad-custom-dns` oneshot re-running with the new three-element list, across wg0-mullvad getting reconfigured. The only thing that would expose the break was **tailscaled losing its session and needing to re-auth** — which happens on reboot.

I rebooted the desktop on 2026-04-10 around 08:51. tailscaled came up, tried to fetch a fresh control key from `ts.dimensiondoor.xyz`, and hit connection timeout. The retry loop continued silently in the background. Most Tailscale-dependent things on the desktop are infrequent: deploy-rs from desktop is rare, terraform-against-openbao is rare, and the kernel itself doesn't care whether Tailscale is up. The only thing I use regularly that goes through Tailscale from this host is the vault MCP in Claude Code — and Claude Code only tries to connect on startup or when I run `/mcp`. I didn't notice until a few hours later when I actually tried to use it.

Investigation initially looked like it would be simple: "Tailscale isn't connecting, check the postmortems for prior fixes." I expected to find one of the three April 7 faults regressed. The first ~8 minutes of investigation confirmed the **opposite**: both the April 8 nftables bypass and the April 7 Mullvad-custom-DNS fix were present in the repo AND loaded at runtime. The systemd oneshot was `active`. `mullvad dns get` returned non-empty custom DNS. Everything looked correct.

The key clue was noticing that `mullvad dns get` returned **three** servers but `resolvectl` status for `wg0-mullvad` showed only **one** — Quad9. Mullvad's daemon was filtering the LAN IPs out of the list it published to systemd-resolved on the tunnel interface. With only Quad9 on the `~.` catch-all link, every DNS query funneled to Quad9, which has no knowledge of the AdGuard split-DNS rewrite, and returned the real Cloudflare answer (the WAN IP). Tailscaled then tried to NAT-hairpin the WAN IP, which OPNsense can't do (per the April 7 postmortem), so the TCP connect timed out.

Tracing the third server (`9.9.9.9`) back through the Nix code led quickly to `privacy.mullvadCustomDns = config.networking.nameservers` in `hosts/desktop/configuration.nix:41`, which pointed at the three-element list in `hosts/_profiles/base.nix:122-126`. `git log -S` then showed the regression was introduced in commit `4bd9a5d` two days earlier.

## Contributing Factors

- **Two config options with opposite semantics share the same shape.** `networking.nameservers` is a fault-tolerant preference list — you *want* a public fallback there, because its purpose is resilience when upstream DNS fails. `privacy.mullvadCustomDns` is a Mullvad filter list — you *don't want* tunnel-reachable entries there, because Mullvad treats the first tunnel-reachable DNS server as authoritative and filters out the rest. Both options take `listOf str`, both contain IP addresses, and both look interchangeable until you reach line-by-line inspection of Mullvad's DNS publishing behavior.
- **The April 7 fix's "do not add public fallbacks" invariant lived only in my head.** The postmortem action item "Set Mullvad custom DNS back to AdGuard" was checked off, but the underlying constraint — that Mullvad's custom DNS must contain ONLY tunnel-unreachable addresses — was not captured in the `privacy.mullvadCustomDns` option description, nor in a comment, nor in an assertion. A future reader (including me) had no way to know the list had a hidden invariant.
- **Mullvad's DNS filtering is undocumented behavior.** When I set two LAN servers in the original fix, Mullvad published them verbatim to `wg0-mullvad`. When I added a third tunnel-reachable server, Mullvad changed behavior and filtered the LAN ones out. The threshold for this filtering isn't documented — I learned it empirically by comparing `mullvad dns get` against `resolvectl`.
- **Latent regression with no signal.** The bug existed from 2026-04-08 17:44 until the next reboot ~40 hours later. Nothing in the config evaluation or `nh os switch` output flagged it. No alert fires when `resolvectl` on `wg0-mullvad` has only a single server.
- **DRY refactor made a hidden coupling invisible.** The original `privacy.mullvadCustomDns = dns.servers` referenced a list specifically named "DNS servers" — nothing in the name suggested it had Mullvad semantics. When I subsequently refactored that to `config.networking.nameservers`, the coupling traveled with it. Neither name communicates the Mullvad constraint.
- **Tailscaled session persistence delayed the symptom.** If tailscaled had immediately lost its session at `nh os switch` time, the break would have been noticed on April 8 while the refactor was fresh in my mind. Instead it manifested two days later when the reboot was the most recent mental hook, and I initially thought "something in today's environment" rather than "something in a commit from Wednesday".
- **Mental shortcut: "both postmortem fixes are in the repo → neither has regressed".** When I verified the April 7 and April 8 fixes were present in code *and* at runtime, I briefly considered the investigation finished. It took noticing the Mullvad DNS list length mismatch to realize a *third* fault had layered on top.

## What I Was Wrong About

- **I assumed sharing the list was DRY.** In reality, it was coincidental naming. The two options happen to store "a list of IP addresses" but their correctness criteria are disjoint. DRY only applies when two things would change *together*; these two don't.
- **I assumed "public DNS fallback" was universally safe.** It's safe for host-level DNS resolution. It's actively harmful when handed to Mullvad as custom DNS.
- **I assumed the April 7 fix was stable as long as the `mullvad-custom-dns` oneshot was active.** The oneshot was active. It was doing exactly what its config told it to do. The problem was that its config had been *semantically* corrupted by a refactor that evaluated correctly and passed pre-commit hooks.
- **I assumed tailscaled would fail visibly at rebuild time if something in its environment changed.** It holds sessions across reboots, across network interface flaps, across systemd unit restarts, and across Mullvad reconfigurations — as long as its stored node key hasn't been refused by the control server. This is deliberate Tailscale design (resilience) but it delays failure detection significantly.
- **I assumed Mullvad publishes custom DNS verbatim.** It doesn't — it filters based on tunnel routability, which creates a nonlinear response to the input list.

## What Helped

- **The April 7 postmortem was specific enough to be runnable as a checklist.** Comparing "what the postmortem says should be true" against "what runtime state shows" found that both April 7 and April 8 fixes were correctly loaded, which immediately narrowed the search space.
- **`resolvectl` output shows per-link DNS state, not just the resolver's final answer.** Without the per-link DNS list showing `9.9.9.9` alone on `wg0-mullvad`, I would not have suspected Mullvad's filtering. `dig @192.168.1.53 ts.dimensiondoor.xyz` returning the correct internal IP (`192.168.1.52`) in parallel to `resolvectl query` returning the wrong public IP was the smoking gun.
- **Git history's `-S` flag (pickaxe) found the introducing commit in one command.** `git log -S "9.9.9.9" -- lib/dns.nix` pointed straight at `4bd9a5d`, and that commit's message explicitly celebrated the change ("Added Quad9 as public fallback"), making the causation unambiguous.
- **Having two previous postmortems in the same cluster.** The April 7 and April 8 documents made the *shape* of the fault recognizable — once I saw the tailscaled connect-timeout symptom, I knew what investigation path to follow.
- **Claude Code's `/mcp` command surfaced the symptom.** Without regularly using the vault MCP, this regression could have sat latent for much longer — potentially until a terraform-against-openbao run or a deploy-rs run from the desktop.
- **The fix was one line in one file.** Once the root cause was known, applying the correction was trivial and reversible via git.

## What Could Have Been Worse

- **If the vault MCP had been the only path to OpenBao from this host.** On the desktop it's not — I can SSH to erebor's public IP and use `bao` locally. But if I'd been mid-deployment relying on vault-agent or a `tofu apply` that needed OpenBao, the fix would have been more time-pressured.
- **If tailscaled had re-authed more recently.** The ~40-hour latent period was lucky in one sense (no deploy was blocked) but unlucky in another (it decoupled the failure from the commit that caused it, making the debug harder).
- **If I'd applied the wrong fix and introduced a fourth fault.** For a few minutes I considered adding a `~dimensiondoor.xyz` routing domain to `eno1` instead of fixing the Mullvad DNS list. That approach would have worked but also would have left the underlying regression in place, meaning **any other host that accidentally depended on Mullvad's custom DNS serving a LAN IP would have silently started hitting Quad9**. The correct fix is at the root, not at the symptom.
- **If this pattern existed on any other desktop/laptop host.** framework13 uses the workstation profile but does not enable `modules.privacy.mullvadCustomDns`, so only ammars-pc was affected. If I added Mullvad to framework13 later, the same regression would apply, because `networking.nameservers` in `base.nix` is inherited by all hosts.
- **If Mullvad's filtering behavior had been *partially* successful instead of fully.** E.g., if Mullvad had kept `192.168.1.53` on `wg0-mullvad` some of the time, the failure would have been intermittent and much harder to reproduce.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

Three distinct patterns layered here:

1. **Invariants that live only in postmortems don't survive refactors.** The April 7 postmortem's "Set Mullvad custom DNS back to AdGuard" action item was a symptom-level fix. The underlying invariant — "Mullvad custom DNS must contain only tunnel-unreachable servers" — was never expressed in code, comments, or assertions, so there was nothing to protect it when I later DRY'd the list. This is a general pattern: any time a postmortem resolves a configuration issue, the fix needs to be encoded **at the point of configuration**, not just applied and forgotten.

2. **Two NixOS options that share a type and a shape can mean opposite things.** `listOf str` is not a contract. The type system can't distinguish "fault-tolerant fallback list" from "must-exclude-tunnel-reachable filter list". The only defense is *naming*, *documentation*, and *not coupling them*. I coupled them for DRY reasons without examining whether the semantics matched.

3. **The Mullvad/Tailscale stack on ammars-pc is still fragile.** This is the third postmortem in this cluster (April 7 triple-fault, April 8 nftables bypass never loaded, April 10 DNS regression). Each fix resolves one interaction and uncovers another. The stack composition — Mullvad nftables, NixOS iptables-nft, Tailscale's own chains, custom bypass rules, systemd-resolved split DNS, AdGuard split-DNS rewrite, OPNsense without NAT hairpin — is load-bearing on ~6 separate layered assumptions, any one of which can fail silently. An alternative architecture (e.g., Headscale reachable via a public HTTPS endpoint from inside the LAN without hairpin; or moving Tailscale off the Mullvad-excluded cgroup and accepting some performance cost; or not running two overlay VPNs on the same host at all) would remove entire classes of this bug.

## Action Items

- [ ] **Document the invariant on `modules.privacy.mullvadCustomDns`.** Update the option description in `modules/nixos/privacy.nix` to explicitly state: "Must contain only LAN / tunnel-unreachable addresses. Public fallbacks like Quad9 will cause Mullvad to filter out the LAN servers and break all split-DNS rewrites via wg0-mullvad. Do not set this to `config.networking.nameservers`." Add an `assert` that rejects any IP outside RFC1918 / ULA ranges.
- [ ] **Decouple Headscale discovery from Mullvad's DNS cooperation.** Add a routing domain for `~dimensiondoor.xyz` on `eno1` in `services.resolved.domains` (or the `systemd.network` equivalent), so systemd-resolved routes those queries through AdGuard regardless of what Mullvad publishes on `wg0-mullvad`. This defends against future regressions of the same invariant.
- [ ] **Add a runtime health check for `resolvectl` on `wg0-mullvad`.** A systemd oneshot that runs after `mullvad-custom-dns` and verifies `resolvectl status wg0-mullvad` contains at least one `192.168.*` server would have caught this break within seconds of the bad `nh os switch`. Fail the activation if the check fails.
- [ ] **Update the 2026-04-07 triple-fault postmortem's action items** with a note that "Set Mullvad custom DNS back to AdGuard" was not a stable fix on its own — it needs to be paired with the invariant documentation above to prevent regression.
- [ ] **Consider eliminating the dual-VPN stack on ammars-pc.** Now that three postmortems are attributable to Mullvad/Tailscale layering, write an ADR evaluating: (a) keeping the current stack with more guardrails, (b) moving Mullvad to a dedicated network namespace instead of a cgroup exclusion, (c) dropping Mullvad from ammars-pc entirely and running it only on a gateway box, (d) using Tailscale's own exit nodes for VPN-like privacy instead of Mullvad. Do not rush this — but commit to the ADR.
- [ ] **Add memory note / CLAUDE.md entry.** Next time I (or Claude) edit `networking.nameservers` or `privacy.mullvadCustomDns`, there should be an obvious reminder not to cross the streams.

## Lessons

- **`list of IPs` is a type, not a contract.** Before DRY'ing two configurations that store the same shape, verify they have the same correctness criteria. If they don't, they must stay separate even if it feels repetitive.
- **Encode postmortem invariants at the point of configuration.** A checked-off action item is not a lasting defense. If the fix was "set this value to X", the code needs to say *why* X and *why not* any other value — as a comment, an assertion, or an option type that rejects invalid inputs. Otherwise the next cleanup commit will quietly reintroduce the bug.
- **Tailscale sessions persist across rebuilds.** A config change that breaks Tailscale auth will not manifest until the next reboot or key refresh. Never assume "it rebuilt fine, it's fine" for Tailscale-adjacent config changes — a brief `sudo systemctl restart tailscaled && sleep 10 && tailscale status` after any Mullvad/nftables/DNS change would have caught this on April 8.
- **When diagnosing Mullvad DNS behavior, always compare `mullvad dns get` against `resolvectl status wg0-mullvad`.** They do not always agree. The resolvectl output is what systemd-resolved (and therefore every process on the system) actually uses; `mullvad dns get` is what Mullvad's daemon *thinks* it's publishing. A discrepancy means Mullvad is filtering the list.
- **Layered fault systems produce layered regressions.** The 6-layer failure chain (DRY refactor → Quad9 in list → Mullvad filter → only public DNS on `wg0-mullvad` → `~.` catch-all → public IP returned → NAT hairpin fail → tailscaled timeout → Tailscale logged out → MCP unreachable) is characteristic of a stack with too many implicit invariants. Each layer looked fine in isolation. Only their composition was broken. When a system has reached this level of layering, individual fixes will continue to expose new interactions until the layering itself is simplified.
- **Trust git pickaxe (`git log -S`) to find the introducing commit.** Once the root cause is identified at the code level, `-S` is the fastest way to find *when* and *why*. In this incident, one pickaxe query turned "unknown regression" into "commit with a celebratory message about adding the poison pill" in under 5 seconds.
