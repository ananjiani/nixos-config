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
   Codeberg (main protected, FF-only)
          |
          +--> Buildbot: eval + build + status
          |    Attic watcher: upload outputs asynchronously
          |    (neither activates a host)
          |
          +--> Comin on 7 servers: poll ~1/min, pull main/testing-*,
          |    substitute from Attic, switch or test locally
          |
          +--> Aragorn 04:30 timer: deploy-rs -> ammars-pc
               (WOL + lock/dirty/CI gates; system then home)
```

| Role | What it does | What it never does |
| --- | --- | --- |
| Codeberg `main` / PRs | Source of truth. Direct push to `main` is blocked. Merges are fast-forward only. | Host activation |
| Buildbot | Checks, builds host closures, and reports status | Deploy / SSH activate |
| Attic (`middle-earth`) | Store watcher uploads outputs asynchronously; hosts use this warm binary cache | Decide what is live |
| Comin (7 servers) | Polls Codeberg, builds/substitutes, `switch` on `main`, `test` on `testing-<host>` | Auto health rollback |
| deploy-rs via Aragorn | Nightly activity-aware desktop deploy; manual recovery path for servers | Routine server convergence |

Required PR check: **`buildbot/nix-build`**.

`buildbot/nix-eval` is **not** required. A warning there can mean eval
succeeded with warnings. Do not block a merge on eval alone.

## Daily normal workflow

1. Push a feature branch.
2. Open a PR to `main`.
3. Wait for **`buildbot/nix-build`** success. The separate Attic upload may still be finishing.
4. Merge (fast-forward only).
5. Servers: Comin starts processing `main` after its next poll (~1 minute). Eval, build, and activation take longer.
6. Desktop (`ammars-pc`): waits for Aragorn's **04:30** local timer. No midday catch-up.

## Risky single-host workflow (`testing-<hostname>`)

Use only for one named host. The target branch name must be exactly
`testing-<hostname>` (example: `testing-aragorn`) and must start from current
`main`. Treat testing branches as disposable: delete one after promotion or
abandonment, then recreate it from current `main` before reuse.

1. Make sure you have console or remote-reboot access outside SSH. A bad test can break the network.
2. Create a feature branch from current `main`.
3. Open a PR from the feature branch to `testing-<hostname>`.
4. Wait for `buildbot/nix-build`, then fast-forward merge into the testing branch.
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
| `denethor` | Comin | Work VLAN; metrics-only OPNsense pinhole to TCP 4243 |
| `ammars-pc` | Aragorn deploy-rs @ 04:30 | Standalone Home Manager; local `nh home switch` stays the fast loop |

## Server behavior (Comin)

Exact module: `modules/nixos/comin.nix`.

- Polls the public Codeberg remote about once per minute.
- Branch `main` → operation **`switch`** (persistent).
- Branch `testing-<hostname>` → operation **`test`** (nonpersistent after reboot).
- Evaluates and builds through the local Nix daemon; prefers Attic substitutes.
- Retention: **3** boot entries, **3** successful deployments, **5** total deployments.
- **No** automatic health rollback. A bad `main` switch stays until you reboot
  to a retained generation or recover with deploy-rs after suspending Comin.
- Auto-reboot is **off**. Metric `comin_need_to_reboot == 1` means schedule a
  supervised reboot; Comin will not reboot for you.

Useful commands on a Comin host:

```bash
sudo comin status
sudo comin events
sudo comin deployment list
journalctl -u comin
sudo comin suspend
sudo comin resume
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
| `CominNeedsReboot` | Kernel/similar change needs a supervised reboot |
| `CominSuspendedUnexpectedly` | Comin suspended ≥ 2h |
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

## Current live state (2026-08-20)

- All **7** Comin servers track `main`; exporters are healthy (including
  Erebor via Tailscale and Denethor via the Work VLAN metrics pinhole).
- Buildbot deploy hook / fleet key removed — CI builds and caches only.
- Branch protection on `main` is live (`buildbot/nix-build` required, FF-only).
- Desktop active/unlocked skip path and new ntfy wording are confirmed.
- Docs/k8s-only pre-WOL filter is implemented in
  `hosts/servers/aragorn/configuration.nix` but **not live** until that change
  merges and Aragorn's Comin switch picks it up.
- First successful **sleeping-desktop / WOL** deploy is still **unconfirmed** —
  exercise that path on purpose.
- Automatic reboots remain off; treat `comin_need_to_reboot` as a schedule item.

## Source map

| Path | Role |
| --- | --- |
| `modules/nixos/comin.nix` | Shared Comin module |
| `hosts/_profiles/server/configuration.nix` | Enables Comin on fleet profile |
| `hosts/servers/denethor/configuration.nix` | Denethor Comin + 4243 firewall |
| `hosts/servers/aragorn/configuration.nix` | Nightly desktop controller |
| `hosts/desktop/configuration.nix` | Desktop NixOS guard + WOL NIC |
| `hosts/desktop/home.nix` | Standalone HM re-check before write |
| `k8s/apps/monitoring/scrapeconfig-infrastructure.yaml` | Comin / node scrapes |
| `k8s/apps/monitoring/helmrelease-kube-prometheus-stack.yaml` | Alert rules |
| `docs/content/adrs/adr-009-2026-08-19-comin-pull-deployments.md` | Decision record |
| `.agents/plans/2026-08-19-comin-buildbot-deployment-flow.md` | Implementation plan history |
