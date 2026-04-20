---
date: 2026-04-20
title: Cold-boot deadlock — Headscale-in-k3s made the cluster unable to recover from a planned shutdown
severity: moderate
duration: ~40 min active recovery, ~5 hrs end-to-end incl. architecture fix
systems: [k3s, headscale, tailscale, openbao, vault-agent, sops-nix, erebor]
tags: [bootstrap, cold-boot, dependency-cycle, migration, ADR-002]
commit: https://codeberg.org/ananjiani/infra/commit/76018ac
---

## Summary

Planned shutdown of the 3 Proxmox hosts for a physical move left the cluster unable to self-recover on power-up. All three k3s servers blocked waiting for `/run/secrets/k3s_token`, which vault-agent couldn't render because it couldn't reach OpenBao at `100.64.0.21:8200` (a Tailscale IP), because tailscaled was logged out, because Headscale was running inside the same k3s cluster that was trying to boot. Manual workaround: decrypt the SOPS-bootstrap `k3s_token` and pipe it into `/run/secrets/k3s_token` on each server to break the cycle. Once k3s came up, Traefik, Headscale, tailscale re-auth, and vault-agent recovered in order without further intervention. Permanent fix: migrate Headscale to erebor (ADR-002, issue #85) — executed the same day, now complete.

## Timeline

All times CST.

- **2026-04-19 ~19:35** - `scripts/lab-shutdown --yes rohan the-shire gondor`. Tailscale disconnected locally; VMs shut down via SSH; frodo via `qm shutdown`; Proxmox hosts halted.
- **2026-04-19 ~19:41** - Machines powered back up (sequential, not all at once). k3s servers begin boot. Journal: `k3s[4487]: Waiting for /run/secrets/k3s_token to be available` repeating every 2s on boromir, samwise, theoden.
- **2026-04-19 19:42:13** - `vault-agent-default.service` first timeout: `error authenticating: Put "http://100.64.0.21:8200/v1/auth/approle/login": dial tcp 100.64.0.21:8200: i/o timeout`. Restart counter climbs from this point.
- **2026-04-20 ~10:35** - Resumed investigation. `ping theoden.lan` fails; `qm list` from rohan works; theoden VM reports as UP. boromir and samwise have been cycling vault-agent restarts for ~15 hours.
- **~10:36** - `tailscale status` on boromir: `You are logged out. The last login error was: fetch control key: Get "https://ts.dimensiondoor.xyz/key?v=131": dial tcp 192.168.1.52:443: connect: no route to host`. Headscale is at the Traefik VIP (192.168.1.52), which is served by k3s, which hasn't started. Cycle identified.
- **~10:38** - Confirmed all 3 k3s servers stuck in identical state. `/run/secrets/` contains only `vault_role_id` and `vault_secret_id` (sops-nix bootstrap); `k3s_token` never materialized.
- **~10:40** - User approved SOPS bypass. Piped `sops -d --extract '["k3s_token"]' secrets/secrets.yaml | ssh root@<host> "install -m 400 /dev/stdin /run/secrets/k3s_token"` to all three servers. File flows through the pipe without appearing in the agent's context.
- **~10:41** - k3s picks up the token on next retry; boromir k3s service active within 30s. Cluster API available: `kubectl get nodes` shows all 4 nodes Ready.
- **~10:43** - `tailscale status` on boromir shows re-authenticated peers. Headscale VIP 192.168.1.52 resolves and serves. Vault-agent on all 3 servers eventually succeeds on its next retry.
- **~10:45** - Cluster recovery confirmed complete. 24 Prometheus alerts firing, mostly warning-level DiskPressure (unrelated — theoden was full; resolved earlier in the day by `nix-collect-garbage`).
- **~11:10** - Conversation with user about architecture: "maybe headscale needs to live on erebor too." Agreed, wrote ADR-002.
- **~11:15 → ~15:45** - Executed the full ADR-002 migration (module changes, erebor deploy, data migration, DNS cutover, k8s cleanup). Two incidental bugs found and fixed along the way (see Contributing Factors).

## What Happened

The homelab has a documented bootstrap separation: secrets live on erebor (OpenBao, ADR-001) so the cluster can start without depending on itself. That separation was incomplete. OpenBao lives on erebor, but it's reachable only via Tailscale. Tailscale needs a coordination server. That coordination server (Headscale) lived inside the k3s cluster. So the bootstrap path was actually erebor → Tailscale → k3s → back to erebor. As long as any one node in the chain stayed warm, the cycle was invisible.

I ran `lab-shutdown` with a 90-second pause between the VMs and the Proxmox hosts. This was enough time for tailscaled on each server to close its session cleanly. When the Proxmox hosts came back up and booted their VMs, tailscaled tried to re-authenticate — and needed to fetch a new control key from Headscale. Headscale wasn't up. k3s wasn't up. vault-agent tried to reach `100.64.0.21:8200` over an interface that had no route. Everything looped.

Initial investigation took a few minutes to identify the cycle because the surface symptom — `k3s: Waiting for /run/secrets/k3s_token` — pointed at sops-nix or vault-agent, not at Tailscale or Headscale. I checked whether rohan was back online first (it wasn't initially — user had powered only two of the three Proxmox hosts) and whether sops-nix was even in play on the servers (it isn't; they use vault-agent for `k3s_token`). Only after confirming tailscale was logged out did the Headscale-in-k3s cycle become visible.

The workaround was straightforward once the cycle was named: the SOPS-encrypted `k3s_token` exists in the repo (as a bootstrap path for hosts that don't use vault-agent, like rivendell), so I could decrypt it locally and push it into the three servers' `/run/secrets/` directory. I piped the plaintext through `ssh ... install /dev/stdin /run/secrets/k3s_token` to avoid the plaintext ever appearing in my agent context, consistent with the standing rule "never read secret values through Claude."

Once `k3s_token` was present, k3s booted within seconds. That brought up Traefik, which brought up the Headscale VIP, which let tailscaled re-auth, which let vault-agent reach OpenBao. vault-agent then overwrote the manually-placed `k3s_token` with its own rendered copy on its next template refresh — the workaround was self-healing.

Afterward, the user observed: if OpenBao lives on erebor specifically to break this cycle, Headscale should too. We wrote ADR-002, then executed it. During the migration, two previously-latent bugs surfaced:

1. **Flake-relative path closure tracking**: I passed the ACL file to Headscale as `aclPolicyFile = ../../../modules/nixos/headscale-acl.json` and rendered it to the settings YAML with `path = toString cfg.aclPolicyFile`. The resulting config contained `/nix/store/<flake-source-hash>-source/modules/nixos/headscale-acl.json`, which was technically correct — but `nix-store -q --references` on the YAML returned empty. The reference wasn't tracked, so the file didn't get copied into the closure, so it wasn't on erebor at activation time. Headscale crash-looped with "no such file or directory." Fixed by switching to `pkgs.writeText "headscale-acl.json" (builtins.readFile cfg.aclPolicyFile)`, which creates a dedicated store derivation.

2. **sops-nix wipes vault-agent's `/run/secrets/` on every activation**: `sops-install-secrets` treats entries in `/run/secrets/` it doesn't own as stale and removes them. vault-agent had already rendered `cloudflare_api_token`, `tailscale_authkey`, etc. earlier in the same boot, but after any subsequent `deploy`, those files vanished and Caddy lost its CF env file. vault-agent doesn't re-render without a SIGHUP or lease renewal. Fixed by adding `system.activationScripts.vault-agent-rehydrate` that runs after `setupSecrets` and restarts `vault-agent-default.service` when active. This wasn't specific to erebor — it would have silently degraded any other host running both sops-nix bootstrap and vault-agent runtime secrets.

## Contributing Factors

- **Bootstrap separation was incomplete.** ADR-001 extracted OpenBao to erebor explicitly to solve this class of problem. Headscale was left in k3s — probably because at the time, the only consumer-of-Headscale-that-might-not-be-up-yet was tailscaled on the k3s hosts themselves, and the chicken-egg wasn't obvious until the OpenBao-on-Tailscale-IP design closed the cycle. The partial extraction looked safe until the first cold boot exercised it.
- **Tailscale sessions persist across reboots.** A node that's been authenticated once keeps a valid session for weeks as long as it can reach the control server before the key expires. In normal operation, nodes rarely re-auth — so the cycle stayed invisible during deploys, activations, single-host reboots, etc. Only a fully cold tailnet (all peers off, sessions expired, Headscale unreachable) surfaces the dependency.
- **The workaround path (SOPS-decrypt + pipe) was unscripted.** The original SOPS secret for `k3s_token` exists in the repo for rivendell, which uses sops-nix-to-file for k3s_token because it doesn't have Tailscale. That same mechanism could have been wired up for the k3s servers as a fallback, but wasn't. Every time this incident recurs (until the architecture is fixed), the operator has to remember the exact pipe sequence from memory or from this postmortem.
- **24 Prometheus alerts were firing simultaneously, most unrelated to this incident.** theoden had a DiskPressure event from earlier in the day (unrelated /nix/store bloat). Several `BlackboxProbeFailed` entries were ambiguous. Cutting through the noise to identify the real critical path took longer than it should.
- **The error surface pointed at the wrong layer.** `k3s: Waiting for /run/secrets/k3s_token` and `vault-agent: error authenticating` both look like secrets-layer problems. The actual problem was in the network layer (tailscale logged out), three hops upstream. Without having previously lived through a full cold-boot, there was no pattern-match for "secrets layer failing means the tailnet is down."
- **Two latent bugs in modules about to be extended.** `toString <flake-relative-path>` producing silent closure misses, and sops-nix wiping vault-agent's output, would both have eventually bitten some other change. They came into focus only because the Headscale migration needed a host (erebor) with both flake-relative files in closures AND vault-agent-rendered secrets under `/run/secrets/`. Neither bug was visible in prior deploys of simpler module shapes.

## What I Was Wrong About

- **I assumed the OpenBao extraction was sufficient to break cold-boot deadlocks.** It wasn't — it only broke the secrets-store side. The reachability side (Tailscale auth) was still in-cluster. ADR-001 was necessary but not sufficient.
- **I assumed vault-agent would retry indefinitely and eventually succeed.** It does retry, but only against the same endpoint. If that endpoint is unreachable because Tailscale is logged out, no amount of retry fixes it — Tailscale must come up first, which requires Headscale, which requires k3s, which requires `k3s_token`. The retry loop was masking the fact that progress was impossible without manual intervention.
- **I initially thought "rohan is down → theoden is down → no quorum" was the whole story.** It wasn't; even after rohan came up, the deadlock persisted on all three k3s servers. Quorum wasn't the issue — bootstrap was.
- **I expected `toString` on a flake-relative path to behave like `"${path}"` for reference tracking.** It doesn't, reliably. The path string appears in the output but the scanner doesn't always register it as a closure reference when the underlying path is a subfile of a `/nix/store/<hash>-source/` directory object. `pkgs.writeText` or `builtins.path` with an absolute path gives a standalone derivation whose reference is always tracked.
- **I assumed sops-nix only managed files it declared.** It's more aggressive than that — it treats the `/run/secrets/` directory as its own, and removes anything it doesn't recognize. Running sops-nix alongside vault-agent is a supported pattern in this repo, but the composition has this foot-gun.

## What Helped

- **SOPS bootstrap for `vault_role_id`/`vault_secret_id` worked.** If sops-nix had also been the `k3s_token` path on servers, the workaround would have been a one-line config change instead of a manual pipe. As it was, at least the SOPS-to-OpenBao bootstrap itself was functional; only the OpenBao-to-k3s_token leg was broken. The SOPS secret itself was in the repo, already encrypted with an age key I had locally.
- **The agent-context rule ("never read secret values through Claude") had a clean solution.** Piping `sops -d | ssh ... install /dev/stdin ...` avoided a plaintext-in-context exposure. Having this rule in place meant I didn't pause to work out a safe extraction pattern — I already had one.
- **deploy-rs magic rollback was disabled (`--auto-rollback false`) for the reattempt deploys.** With it enabled, any transient failure during activation would have reverted the new closure, making iterative debugging much slower.
- **Local `nix build` of erebor's toplevel before every deploy.** The `toString` → `pkgs.writeText` fix was validated locally by checking `nix-store -q --references` on the rebuilt `headscale.yaml` before sending a deploy. Caught the fix's correctness before it touched production.
- **Flux reconcile on push made k8s cleanup ceremony-free.** After merging the Phase 5 commit, one `flux reconcile source git flux-system && flux reconcile kustomization apps` removed HelmRelease, IngressRoute, Certificate, ConfigMap, PVC, and namespace in under 30 seconds.
- **The user suggested the architectural fix.** "Maybe headscale needs to live on erebor too" reframed the incident from "how do we recover faster" to "why are we recovering at all?" — which unlocked the ADR and the migration.

## What Could Have Been Worse

- **If the age key on the operator workstation had been unavailable.** The SOPS workaround requires the age private key at `~/.config/sops/age/keys.txt`. If my workstation had been down (or the key rotated without re-encryption), the bypass path would have been unavailable and the cluster would have stayed down until I physically accessed a server with its own age key.
- **If OpenBao on erebor had been sealed.** AWS KMS auto-unseal handles normal restarts, but a KMS outage or a manual seal would have made OpenBao unreachable even after Tailscale came up. The workaround restores k3s, not OpenBao state.
- **If `noise_private.key` had been regenerated instead of migrated.** The migration preserves this key, so existing nodes re-auth seamlessly. If I'd let Headscale generate a fresh key on erebor, every tailnet peer would have required manual re-registration — including pixel9 and other intermittent clients that might not reconnect for weeks.
- **If the DNS flip had been done before Caddy was fully working on erebor.** Caddy obtained its LE cert via DNS-01 while `ts.dimensiondoor.xyz` still pointed at the homeserver IP (DNS-01 doesn't need the A record to point anywhere specific). If I'd flipped DNS first and then deployed Caddy, any client contacting the new IP would have gotten a connection refused until Caddy finished. Sequencing was lucky, not principled.
- **If the two latent bugs had only shown up in the *next* migration**. The `toString`-closure gotcha and sops-nix rehydrate issue would likely have been harder to debug separately, months later. They happened to surface together here because this was the first migration that exercised both patterns on erebor at once.

## Is This a Pattern?

- [x] Pattern: Revisit the approach

Two patterns:

1. **Partial bootstrap extraction is worse than none.** ADR-001 extracted OpenBao to erebor for bootstrap reasons but stopped before extracting the Tailscale control plane it depends on. The result is a system that *looks* like it has a clean bootstrap separation (OpenBao is outside the cluster!) but actually has a three-hop cycle hidden inside it. Going forward, any piece of infrastructure that's in the bootstrap path needs to follow the full chain and confirm nothing loops back into the cluster. ADR-002 closes this specific cycle, but the principle is general.

2. **Activation-script composition is load-bearing and undefended.** sops-nix wiping `/run/secrets/` and vault-agent not auto-re-rendering is exactly the kind of interaction that only surfaces when you try to use both together with time-sensitive consumers (Caddy needing its env file *right now*). The repo has been running both for weeks without hitting this because the servers using vault-agent happen to not have any activation-time-sensitive consumers of its output. Adding Caddy on erebor was the first combination that exposed it. The fix is local (activation script), but there may be other latent interactions in the module composition that a wider audit would find.

## Action Items

- [x] **Migrate Headscale to erebor (ADR-002).** Completed same day: module changes, deploy, data migration, DNS cutover, k8s cleanup. Commits `efa5ae2`, `d9cb381`, `76018ac`, `63cb4e5`, `d6f6813`.
- [x] **Fix closure tracking for flake-relative paths used in settings.** `modules/nixos/headscale.nix` now uses `pkgs.writeText` for the ACL file. Memory entry added to prevent recurrence in other modules.
- [x] **Fix sops-nix / vault-agent `/run/secrets/` collision.** `modules/nixos/vault-agent.nix` now runs `system.activationScripts.vault-agent-rehydrate` after `setupSecrets` to restart vault-agent. This repairs latent issues on any host with both modules, not just erebor.
- [ ] **Verify the cold-boot fix.** Run `scripts/lab-shutdown --all && scripts/lab-startup --all` when convenient and confirm cluster comes up without manual SOPS intervention. This is the ADR-002 confirmation criterion; until exercised, the fix is theoretical.
- [ ] **Add a SOPS-bootstrap fallback for `k3s_token` on servers.** Even with Headscale on erebor, a secondary cold-boot fault (erebor down, KMS outage, Cloudflare DNS outage) could block `k3s_token` rendering. Letting servers fall back to a SOPS-decoded path (matching what rivendell already does) would make cold-boot survive one more layer of degradation. Small config change; worth having as belt-and-suspenders.
- [ ] **Document the cold-boot recovery workaround in `scripts/lab-startup` or a runbook.** The `sops -d --extract | ssh ... install /dev/stdin` pattern worked but was ad-hoc. If cold-boot regresses (bug, state drift, new cycle), having the exact command in a script saves the operator from re-deriving it under stress.
- [ ] **Audit other module compositions for activation-script interactions.** sops-nix and vault-agent weren't the only possible collision. Modules that write to `/run/`, `/etc/`, or systemd unit state during activation could have similar hidden interactions. A short checklist ("does your activation script run before or after X?") added to `modules/nixos/README` or equivalent would help catch the next one at design time instead of discovery time.

## Lessons

- **A bootstrap cycle that closes through the tailnet is invisible until the tailnet is fully cold.** Partial outages (one node, one service, one reboot) don't exercise the full dependency graph because persistent sessions mask it. The only way to validate that bootstrap works is a full simultaneous shutdown-and-restart, which nobody does voluntarily.
- **When secrets layer errors appear during boot, check the network layer three hops upstream.** "Waiting for /run/secrets/X" is a symptom. The cause is often that the process producing X can't reach its source, which is often a network/auth problem dressed up as a secrets problem.
- **`toString` is not a safe coercion for paths that need closure tracking.** Use `"${path}"` for string interpolation (which preserves reference tracking in most cases), or `pkgs.writeText` / `builtins.path` with absolute paths when you need a dedicated derivation. Never `toString` a flake-relative path that will be embedded in a config file.
- **Activation scripts can invalidate runtime state without failing the activation.** `switch-to-configuration` returned success even though vault-agent's rendered files were silently removed, because the removal was an intentional sops-nix cleanup. Watch for "deploy succeeded but the service is broken a minute later" as a signature of this class of bug.
- **User observations often contain the right architectural fix.** "Maybe headscale needs to live on erebor too" took ~10 seconds for the user to say and completed the bootstrap separation that ADR-001 had started. The hardest debugging step is sometimes noticing that the debugging itself is the wrong frame.
