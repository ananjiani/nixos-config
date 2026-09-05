---
date: 2026-08-20
title: Deployment Reference
systems:
  [
    comin,
    buildbot,
    attic,
    deploy-rs,
    aragorn,
    boromir,
    samwise,
    theoden,
    rivendell,
    erebor,
    denethor,
    ammars-pc,
  ]
tags: [deployment, gitops, ci, monitoring, operations]
---

# Deployment Reference

Operator guide for how code reaches hosts. Rationale lives in
[ADR-009](adrs/adr-009-2026-08-19-comin-pull-deployments.md).

## Architecture (one screen)

```text
  feature branch / PR
          |
          v
   Codeberg (main protected, squash merge)
          |
          +--> Buildbot: eval + build + status
          |    Attic watcher: upload outputs asynchronously
          |    (neither activates a host)
          |
          +--> Comin on 7 servers: poll ~1/min, pull main/testing-*
          |    Six SOPS servers wait for NixCI + cache.nix-ci.com, then
          |    substitute/build and switch (or test). Denethor is ungated.
          |
          +--> Aragorn 04:30 timer: deploy-rs -> ammars-pc
               (WOL + lock/dirty/CI gates; system then home)
```

| Role | What it does | What it never does |
| --- | --- | --- |
| Codeberg `main` / PRs | Source of truth. Direct push to `main` is blocked. PRs to `main` use squash merges. | Host activation |
| Buildbot | Checks, builds host closures, and reports status | Deploy / SSH activate |
| Attic (`middle-earth`) | Store watcher uploads outputs asynchronously; hosts use this warm binary cache | Decide what is live |
| Comin (7 servers) | Polls Codeberg, builds/substitutes, `switch` on `main`, `test` on `testing-<host>` | Auto health rollback |
| Comin NixCI gate (6 SOPS servers) | After eval, confirm `build` only when NixCI is green for that SHA and the host output-path narinfo is in cache.nix-ci.com (or cache is down). Not a full-closure guarantee. | Blanket `comin confirmation accept`; Codeberg/Buildbot status |
| deploy-rs via Aragorn | Nightly activity-aware desktop deploy; manual recovery path for servers | Routine server convergence |

Required PR check: **`buildbot/nix-build`**.

`buildbot/nix-eval` is **not** required. A warning there can mean eval
succeeded with warnings. Do not block a merge on eval alone.

## Daily normal workflow

1. Push a feature branch.
2. Open a PR to `main`.
3. Wait for **`buildbot/nix-build`** success on the PR head. The separate Attic upload may still be finishing.
4. Squash-merge. An outdated PR can still merge without conflicts after that required head check passes.
5. Buildbot checks the new squash commit on `main`. That SHA is what hosts consume — not the old PR head.
6. Servers: Comin polls (~1 minute) and evaluates. The six SOPS servers wait for the NixCI gate before build; Denethor builds immediately. Then switch (or test).
7. Desktop (`ammars-pc`): waits for Aragorn's **04:30** local timer and a green `buildbot/nix-build` on that exact `main` SHA. No midday catch-up.

## Risky single-host workflow (`testing-<hostname>`)

Use only for one named host. The target branch name must be exactly
`testing-<hostname>` (example: `testing-aragorn`) and must start from current
`main`. Treat testing branches as disposable: delete one after promotion or
abandonment, then recreate it from current `main` before reuse.

1. Make sure you have console or remote-reboot access outside SSH. A bad test can break the network.
2. Create a feature branch from current `main`.
3. Open a PR from the feature branch to `testing-<hostname>`.
4. Wait for `buildbot/nix-build`, then fast-forward merge into the testing branch. Choose FF-only for `testing-*` even though the repo default is squash.
5. That host's Comin uses operation **`test`** (temporary activation). Other hosts ignore the branch.
6. Verify behavior on that host.
7. If bad, reboot to the previous persistent `main` generation. Fix or abandon the testing branch.
8. If good and `main` is unchanged, open a PR from the testing branch to `main`.
9. If `main` moved, rebase the feature on current `main`, recreate the testing branch, wait for CI, and test the new SHA again. Promote only the exact SHA you verified.

**Attic reuse:** the separate store watcher uploads outputs asynchronously.
When those outputs are ready, Comin substitutes them from Attic instead of
rebuilding from scratch.

## Host matrix

| Host | Deploy owner | Notes |
| --- | --- | --- |
| `aragorn` | Comin | Also runs the `ammars-pc` nightly controller |
| `boromir` | Comin | Manual recover: see Boromir exception below |
| `samwise` | Comin | |
| `theoden` | Comin | Attic cache host |
| `rivendell` | Comin | No Tailscale |
| `erebor` | Comin | Exporter scraped via Tailscale (`100.64.0.21:4243`), not public |
| `denethor` | Comin (no NixCI gate) | Work VLAN; metrics-only OPNsense pinhole to TCP 4243. Ungated: no SOPS NixCI netrc. |
| `ammars-pc` | Aragorn deploy-rs @ 04:30 | Standalone Home Manager; local `nh home switch` stays the fast loop |

## Server behavior (Comin)

Exact module: `modules/nixos/comin.nix`.

- Polls the public Codeberg remote about once per minute.
- Branch `main` → operation **`switch`** (persistent).
- Branch `testing-<hostname>` → operation **`test`** (nonpersistent after reboot).
- Evaluates and builds through the local Nix daemon; prefers substitutes.
- **NixCI gate** (`modules.comin.ciGate`, default off) is on for the six
  SOPS servers in `hosts/_profiles/server/configuration.nix`
  (aragorn, boromir, samwise, theoden, erebor, rivendell). Denethor,
  workstations, WSL, and the ISO are unchanged.
- When the gate is on, Comin `buildConfirmer` is **manual**. `comin-ci-gate.timer`
  runs `comin-ci-gate.service` about every 60s after the last run ends.
  The first generation that enables the gate still uses the previous (ungated)
  config; Comin picks up `manual` mode on the restart that generation causes.
- Per pending generation, after eval: NixCI `GET https://nix-ci.com/cb:ananjiani:infra/<branch>/<sha>`
  must be HTTP 200 with `commit`/`ref` exact match and suite `status=success`,
  plus `checks.x86_64-linux.nixos-<hostname>` success/cached (configure + eval
  present and green, nonempty `runs`). Codeberg/Buildbot status is ignored.
- Cache tri-state, using `/run/secrets/nix_ci_netrc` as root: **approve** if
  `nix-cache-info` and the pending generation's exact output-path narinfo are
  200 (References are parsed for validity, not walked); **wait** (retry the
  same UUID, do not fail the build) if the cache is healthy but that root
  narinfo is 404, unexpected 3xx/4xx, or metadata is invalid; **fallback
  approve** + metric on 401/403, missing netrc, timeouts, or 5xx. CI errors
  never fall back. Native Nix may rebuild missing dependencies and their
  cached parents even when NixCI and the cache look healthy. A native Nix
  test with a cached parent and missing child completed by rebuilding both.
  This works around missing cache entries; it does not guarantee build-once
  behavior or prove that local-build flags caused the gap. Local/remote
  builds stay enabled.
- Retention: **3** boot entries, **3** successful deployments, **5** total deployments.
- **No** automatic health rollback. A bad `main` switch stays until you reboot
  to a retained generation or recover with deploy-rs after suspending Comin.
- Auto-reboot is **on** for aragorn/boromir/samwise/theoden/erebor/denethor via
  `comin-auto-reboot.timer` (`modules.comin.autoReboot`). It reboots only when
  `comin_need_to_reboot == 1`, uptime > 1h, no logged-in users, and any host
  `preRebootCheck` passes. `Persistent=false` (missed window → try tomorrow).
  rivendell is excluded. Stagger: aragorn 04:00, boromir 04:15, samwise 04:30,
  theoden 04:45, erebor 05:00, denethor 05:15. See
  [ADR-014](adrs/adr-014-2026-09-04-comin-auto-reboot.md).

Useful commands on a Comin host:

```bash
sudo comin status
sudo comin events
sudo comin deployment list
journalctl -u comin
sudo comin suspend
sudo comin resume
sudo comin confirmation show
journalctl -u comin-ci-gate.service
systemctl list-timers comin-ci-gate.timer
```

## Desktop flow (`ammars-pc`)

Controller: Aragorn systemd timer `ammars-pc-deploy.timer` at **04:30** local.
`Persistent=` is off — a missed window does **not** catch up midday.

Each run:

1. Reads exact `main` SHA from Codeberg.
2. Requires the latest `buildbot/nix-build` status for that SHA to be success.
3. Path filter (after CI, before WOL): compare that SHA to the actual last
   deployed SHA (`last-success`). If every changed path is under `docs/` or
   `k8s/`, finish as `ignored` — no SSH, no WOL, no deploy. Empty
   `last-success`, empty diff, mixed paths, or any classification failure
   fail open and continue to deploy.
4. If the PC is offline and a newer green SHA is pending, sends WOL and waits
   up to **180 seconds** (36 × 5s) for SSH.
5. Safety gate on the desktop (must pass):
   - `niri` absent **or** `swaylock` present (unlocked session → skip)
   - not running `nix-gc` / `nix-optimise`
   - checkout clean, on `main`, fast-forward-safe to the exact SHA
6. Drops `/run/ammars-pc-auto-deploy` marker; marker is rechecked before NixOS
   activation and again before standalone Home Manager activation.
7. Activates **system**, then **home** (`profilesOrder`).
8. Clears pending on success. Missed/blocked releases stay pending for the
   next night. `ignored` clears pending without updating `last-success`;
   `last-ignored` stops repeat ntfy for that SHA. The next relevant commit
   still diffs from the actual deployed SHA.

Local day-to-day loop on the desktop:

```bash
nh home switch
# never: nix run home-manager -- switch
```

A manual one-shot bypasses the controller's CI, lock, activity, maintenance,
and marker gates. Use it only while supervised. First lock the desktop, stop
or wait for Nix maintenance, and make sure its checkout is clean and on
`main`. Deploy the exact green commit from a clean temporary worktree:

```bash
release=$(mktemp -d)
git worktree add --detach "$release" <green-sha>
(cd "$release" && nix develop --command deploy .#ammars-pc)
git worktree remove "$release"
```

Normal path remains the nightly Aragorn controller.

### Desktop result table (metrics + ntfy)

Metric: `ammars_pc_deploy_result{result="..."}` (one-hot). During the
Erebor ntfy migration soak, the unauthenticated desktop publisher remains on
`https://ntfy-home.dimensiondoor.xyz/monitoring`, the TLS-valid internal alias
for the in-cluster service. Move it to the permanent public endpoint only after
provisioning a dedicated least-privilege publisher identity.

| Result | Meaning | ntfy title pattern |
| --- | --- | --- |
| `success` | Deployed while already reachable | `ammars-pc deployed <sha8>` |
| `woke_success` | WOL succeeded, then deploy succeeded | `ammars-pc woke and deployed <sha8>` |
| `active` | Skipped: niri unlocked | `ammars-pc skipped: session unlocked` |
| `wake_failed` | Skipped: WOL / SSH never came up | `ammars-pc skipped: wake failed` |
| `dirty` | Skipped: dirty git / not on main / not ff-safe | `ammars-pc skipped: dirty checkout` |
| `maintenance` | Skipped: **CI not green** *or* `nix-gc`/`nix-optimise` active (also git fetch failure in the safety script) | `ammars-pc skipped: CI or maintenance` |
| `failure` | deploy-rs failed or rolled back (or status API / marker failure) | `ammars-pc deploy failed <sha8>` |
| `ignored` | Docs/k8s-only green commit; no wake/deploy | `ammars-pc skipped: no desktop changes` |

Skipped and failed results leave the SHA **pending** for the next night.
`ignored` does **not**: it clears pending, writes `last-ignored`, and leaves
`last-success` unchanged so the next relevant commit still compares from the
last real deploy.

## Monitoring

- Comin Prometheus exporter: port **4243** on each Comin host.
- Desktop deploy metrics: Aragorn node exporter **textfile** collector
  (`ammars_pc_deploy_*`).
- Comin NixCI gate textfile: `/var/lib/comin-gate/textfile/comin-ci-gate.prom`
  (`comin_nixci_cache_error`, `comin_nixci_gate_last_success_timestamp_seconds`).
  Scraped via `job=nixos-node-exporter` (includes Erebor at `100.64.0.21:9100`).
- Scrape config: `k8s/apps/monitoring/scrapeconfig-infrastructure.yaml`.
- Alert rules: `k8s/apps/monitoring/helmrelease-kube-prometheus-stack.yaml`
  (`comin-alerts`, `desktop-deploy-alerts`).

| Alert | Meaning |
| --- | --- |
| `CominExporterDown` | Cannot scrape Comin; deploy monitoring is blind |
| `CominFetchFailed` | Last Git fetch failed |
| `CominEvalFailed` | Last Nix evaluation failed |
| `CominBuildFailed` | Last Nix build failed (check Attic / builders) |
| `CominDeploymentFailed` | Last switch/test failed |
| `CominNeedsReboot` | Need-reboot metric stuck (auto-reboot skipped or failing) |
| `CominSuspendedUnexpectedly` | Comin suspended ≥ 2h |
| `CominNixCiCacheError` | Aggregated: gated hosts cannot auth/reach cache.nix-ci.com (not 404-wait) |
| `AmmarsPcDeployPendingTooLong` | Pending desktop release older than 24h |
| Generic failed-unit alert | Also covers hard failures of `ammars-pc-deploy.service` |

## Recovery runbooks

### A) Bad `testing-*` activation

Test activations are nonpersistent.

1. Reboot the host.
2. It boots the previous unchanged `main` generation.
3. Fix the branch, or abandon it. Do not merge until verified.

### B) Bad `main` / current generation on a server

1. Stop Comin from racing you:

```bash
sudo comin suspend
```

2. Pick one recovery path:

- Reboot into a retained good boot generation, **or**
- Deploy an exact known-good commit from a clean temporary worktree:

```bash
recovery=$(mktemp -d)
git worktree add --detach "$recovery" <known-good-sha>
(cd "$recovery" && nix develop --command deploy .#<host>)
git worktree remove "$recovery"
```

Boromir only, while the ComfyUI activation bug remains, use these flags inside
the temporary worktree:

```bash
nix develop --command deploy .#boromir --auto-rollback false --magic-rollback false
```

Do **not** disable rollback on other hosts as a habit.

3. Fix `main` (revert / forward fix, green `buildbot/nix-build`, merge).
4. Only then:

```bash
sudo comin resume
```

5. Confirm with `sudo comin status` and `journalctl -u comin`.

## Desktop checks (on Aragorn)

```bash
systemctl list-timers ammars-pc-deploy.timer
journalctl -u ammars-pc-deploy.service
```

## Current live state (2026-09-02)

- All **7** Comin servers track `main`; exporters are healthy (including
  Erebor via Tailscale and Denethor via the Work VLAN metrics pinhole).
- Buildbot deploy hook / fleet key removed — CI builds and caches only.
- Codeberg requires `buildbot/nix-build` for `main`, allows mergeable outdated PRs, and defaults to squash merge.
- Desktop active/unlocked skip path and new ntfy wording are confirmed.
- Docs/k8s-only pre-WOL filter is implemented in
  `hosts/servers/aragorn/configuration.nix` but **not live** until that change
  merges and Aragorn's Comin switch picks it up.
- First successful **sleeping-desktop / WOL** deploy is still **unconfirmed** —
  exercise that path on purpose.
- Auto-reboot timers cover need-reboot on the six enabled servers; rivendell still needs a manual reboot when the metric is set.

## Source map

| Path | Role |
| --- | --- |
| `modules/nixos/comin.nix` | Shared Comin module (optional `ciGate`) |
| `modules/nixos/comin-ci-gate.py` | NixCI + cache confirmer helper |
| `hosts/_profiles/server/configuration.nix` | Enables Comin on fleet profile |
| `hosts/servers/denethor/configuration.nix` | Denethor Comin + 4243 firewall |
| `hosts/servers/aragorn/configuration.nix` | Nightly desktop controller |
| `hosts/desktop/configuration.nix` | Desktop NixOS guard + WOL NIC |
| `hosts/desktop/home.nix` | Standalone HM re-check before write |
| `k8s/apps/monitoring/scrapeconfig-infrastructure.yaml` | Comin / node scrapes |
| `k8s/apps/monitoring/helmrelease-kube-prometheus-stack.yaml` | Alert rules |
| `docs/content/adrs/adr-009-2026-08-19-comin-pull-deployments.md` | Decision record |
| `docs/content/adrs/adr-014-2026-09-04-comin-auto-reboot.md` | Auto-reboot decision record |
| `.agents/plans/2026-08-19-comin-buildbot-deployment-flow.md` | Implementation plan history |
