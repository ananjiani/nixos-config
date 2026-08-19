# Comin, Buildbot, and Desktop Deployment Flow

**Date:** 2026-08-19

**Status:** Repository implementation complete; live rollout pending
**Decision:** Use Comin for routine server convergence, Buildbot for CI and Attic, and activity-aware deploy-rs for `ammars-pc`. Keep deploy-rs as the server recovery path. Steam Deck is out of scope.
**ADR:** `docs/content/adrs/adr-009-2026-08-19-comin-pull-deployments.md`

## Implementation status

- [x] Repository code and configuration implemented.
- [x] Full flake check, pre-commit, targeted host builds, YAML parsing, and OpenTofu validation pass.
- [x] Independent final review passes with no blocker, high, or medium findings.
- [ ] Protect Codeberg `main` and require `buildbot/nix-build`.
- [ ] Run `tofu plan` and apply the reviewed OPNsense rule.
- [ ] Deploy Theoden manually to remove the old Buildbot deploy hook.
- [ ] Bootstrap and pilot Comin one host at a time.
- [ ] Run the first `ammars-pc` Wake-on-LAN deployment while supervised.

## Goal

Stop configuration drift without making quick desktop dotfile work slow.

- Buildbot checks and builds code. It never deploys.
- Attic stores successful Nix build outputs.
- Comin pulls and deploys released server configurations.
- Aragorn deploys `ammars-pc` with deploy-rs only while the desktop is safe to update.
- `nh home switch` remains the fast local loop for desktop dotfile changes.

## Final architecture

```text
Feature branch
      |
      v
PR to testing-<hostname>
      |
      v
Buildbot evaluates and builds every flake check
      |
      +--> successful outputs are uploaded to Attic
      |
      v
Fast-forward merge to testing-<hostname>
      |
      v
Comin on that host downloads from Attic
      |
      v
switch-to-configuration test
      |
      +--> bad: reboot to the existing main generation and fix the branch
      |
      +--> good: open PR from testing-<hostname> to main
                         |
                         v
              buildbot/nix-build must pass
                         |
                         v
                fast-forward merge to main
                         |
             +-----------+-----------+
             |                       |
             v                       v
      Comin servers             ammars-pc
      pull and switch      Aragorn deploys at 04:30
                            only when locked and clean
```

```text
Buildbot  = evaluate, build, report CI status
Attic     = cache successful Nix store outputs
Comin     = routine server deployment
Deploy-rs = ammars-pc deployment and server recovery
```

## Settled scope

- [ ] Use Comin on `aragorn`, `boromir`, `samwise`, `theoden`, `rivendell`, `erebor`, and `denethor`.
- [ ] Keep standalone Home Manager on `ammars-pc`; do not embed it into NixOS.
- [ ] Keep both existing deploy-rs profiles for `ammars-pc`, ordered `system` then `home`.
- [ ] Keep deploy-rs nodes for servers as a manual recovery path; do not schedule them when Comin owns the host.
- [ ] Keep Buildbot and Attic; remove only Buildbot's deployment behavior and fleet SSH authority.
- [ ] Keep Steam Deck out of this change.
- [ ] Keep automatic reboots disabled. Alert when a reboot is needed.

## Phase 1 — Make `main` a safe release branch

- [ ] Add Codeberg branch protection for `main`.
- [ ] Block direct pushes to `main` for the normal workflow.
- [ ] Require pull requests before merge.
- [ ] Require the `buildbot/nix-build` status to succeed.
- [ ] Do not require `buildbot/nix-eval` yet; it currently reports `warning` when evaluation succeeds with warnings.
- [ ] Require fast-forward merges so the commit on `main` is the exact commit Buildbot checked.
- [ ] Confirm Renovate cannot merge until `buildbot/nix-build` succeeds.
- [ ] Verify the rule with `tea api repos/ananjiani/infra/branch_protections` without printing tokens.

**Done check:** a failing test PR cannot merge into `main`, a green PR can fast-forward, and direct pushes are blocked.

## Phase 2 — Remove deployment from Buildbot

- [ ] Edit `hosts/servers/theoden/configuration.nix` and remove the custom deployment `postBuildSteps`/`deployScript` path.
- [ ] Keep Buildbot evaluation, per-check builds, Codeberg statuses, Prometheus metrics, alerts, and Attic uploads.
- [ ] Confirm Buildbot still builds every real NixOS host in `checks.x86_64-linux` and the standalone Home Manager checks in `flake.nix`.
- [ ] Deploy this change to Theoden manually before enabling Comin elsewhere.
- [ ] Confirm a PR branch named `main` cannot cause any target activation after the deployment hook is gone.
- [ ] Add a dedicated Aragorn deploy key using the existing secret-management pattern before removing the Buildbot key.
- [ ] Restrict the Aragorn public key to Aragorn's expected LAN/Tailscale source addresses and pin target SSH host keys.
- [ ] Remove the Buildbot worker's fleet deployment private key and its root authorization from `modules/nixos/ssh.nix`.
- [ ] Rotate the retired Buildbot deployment key after the new Aragorn recovery key works.

**Done check:** Buildbot can build and upload to Attic but has no path or credential that can switch a fleet host.

## Phase 3 — Add the shared Comin module

- [ ] Add the maintained `nlewo/comin` flake input in `flake.nix`, following the repository's nixpkgs input policy.
- [ ] Update `flake.lock`.
- [ ] Create `modules/nixos/comin.nix` as a traditional NixOS service module and stage it immediately with `git add modules/nixos/comin.nix`.
- [ ] Export/import the module through the existing `modules/nixos/default.nix` pattern.
- [ ] Configure the public Codeberg repository URL; no repository token is needed.
- [ ] Configure `main` with operation `switch`.
- [ ] Keep the default per-host branch name `testing-${hostname}` with operation `test`.
- [ ] Keep Comin's force-push protection for `main` and its rule that testing branches must be on top of `main`.
- [ ] Keep deployment/profile retention so previous boot entries remain available.
- [ ] Enable the Prometheus exporter on port `4243` only on the interface/network used by the monitoring stack.
- [ ] Keep Comin's desktop service disabled on servers.
- [ ] Document in the module option text that Comin performs local evaluation and asks the target Nix daemon to build; Attic and configured remote builders may satisfy the build.

**Done check:** every configured host evaluates a Comin service that watches only `main` and its own `testing-<hostname>` branch.

## Phase 4 — Preserve the CI-to-Attic-to-Comin flow

- [ ] Keep Buildbot running on ordinary PRs and PRs targeting `testing-<hostname>`.
- [ ] Use this testing workflow for risky host changes:
  - [ ] Create a feature branch on top of current `main`.
  - [ ] Open a PR from the feature branch to `testing-<hostname>`.
  - [ ] Wait for `buildbot/nix-build` to succeed and for Attic uploads to finish.
  - [ ] Fast-forward the green commit into `testing-<hostname>`.
  - [ ] Let only the associated host deploy it in Comin test mode.
- [ ] Treat “test passed” as both: Comin activation succeeded, and the operator verified the changed service or behavior.
- [ ] Treat “test failed” as either: evaluation/build/activation failed, or the running host behaves incorrectly.
- [ ] On a failed test, reboot to the unchanged `main` boot generation, then delete/reset the testing branch and fix the feature branch.
- [ ] On a good test, open a PR from `testing-<hostname>` to `main`.
- [ ] Require `buildbot/nix-build` to build all configured host checks before the main PR can merge.
- [ ] Accept the small repeated evaluation on the testing/main PRs; expensive builds should already exist in Buildbot's store and Attic.
- [ ] Watch for actual duplicate compilation during the pilot before adding any Buildbot branch filter.

**Done check:** a testing deployment normally substitutes from Attic, only the named host runs it, and a reboot returns that host to `main`.

## Phase 5 — Pilot and roll out Comin on servers

- [ ] Bootstrap Comin on Aragorn with the existing manual deploy-rs path.
- [ ] Push a green commit through `testing-aragorn` and confirm `comin status` reports the expected fetch, build, and test deployment.
- [ ] Reboot Aragorn after a harmless test and confirm it boots the previous `main` generation.
- [ ] Promote the tested commit to `main` and confirm Aragorn performs a normal switch.
- [ ] Enable the remaining servers one at a time, using each host's testing branch before promotion.
- [ ] Roll out in this order: `samwise`, `boromir`, `rivendell`, `erebor`, `theoden`, then `denethor`.
- [ ] On Theoden, confirm a Comin switch does not leave Buildbot's worker in a failed state; add a confirmation delay only if real deployments interrupt active builds.
- [ ] Keep Denethor last because Comin evaluation occurs locally on its 4 GiB VM.
- [ ] Keep deploy-rs automation disabled on every host after Comin is enabled there.

**Done check:** all seven servers converge from `main` through Comin, expose healthy metrics, and have a tested boot/recovery path.

## Phase 6 — Give Denethor public Attic access

- [ ] Keep Denethor isolated from `theoden.lan`, the LAN CA, Tailscale, and other homelab services.
- [ ] Edit `hosts/servers/denethor/configuration.nix` and add `https://attic.dimensiondoor.xyz/middle-earth?priority=10` to its forced public substituter list.
- [ ] Keep the existing `middle-earth` trusted public key inherited from the base profile.
- [ ] Confirm the endpoint remains reachable from Denethor over normal public HTTPS.
- [ ] Confirm a Denethor Comin build substitutes its toplevel from Attic after Buildbot has built the same commit.
- [ ] Measure evaluation memory and cache misses during `testing-denethor`.
- [ ] Add Aragorn as a Nix remote builder only if real cache misses exceed Denethor's memory or build-time limits.
- [ ] Add a `prometheus_scrapers` host alias in `terraform/vlans.tf` with the k3s node LAN addresses:
  - [ ] `192.168.1.21` (`boromir`).
  - [ ] `192.168.1.26` (`samwise`).
  - [ ] `192.168.1.27` (`theoden`).
  - [ ] `192.168.1.29` (`rivendell`).
- [ ] Add a narrow OPNsense LAN rule in `terraform/opnsense.tf`: source `prometheus_scrapers`, destination the existing `denethor` alias, protocol TCP, destination port `4243`.
- [ ] Place the metrics rule after admin SSH and before the blanket LAN-to-Work block: SSH sequence `4`, metrics sequence `5`, block sequence `6`.
- [ ] Keep the Work-to-private-networks block unchanged so Denethor still cannot initiate connections to the LAN, k3s, or Tailscale.
- [ ] Bind Denethor's Comin exporter to `10.30.30.10:4243`, keep Comin debug mode off, and open only TCP `4243` on `ens18` in the NixOS firewall.
- [ ] Run `tofu plan` and check that only the alias, one pass rule, and the block sequence change.
- [ ] Apply the OPNsense change only after the plan matches; then confirm the Prometheus request source matches one of the four k3s node addresses.

**Done check:** Denethor downloads normal build outputs from public Attic, Prometheus can read only its Comin metrics, and every other LAN/Work path remains blocked.

## Phase 7 — Keep Erebor on its existing public Attic path

- [ ] Keep `hosts/servers/erebor/configuration.nix` using `https://attic.dimensiondoor.xyz/middle-earth?priority=10`.
- [ ] Keep the existing external Attic availability monitor.
- [ ] Confirm Erebor's Comin deployment substitutes from the public endpoint instead of trying `theoden.lan`.
- [ ] Remove any stale Buildbot deployment comment that says Erebor substitutes through a path it does not actually use.

**Done check:** Erebor can update through Comin without LAN reachability or a full closure push from Buildbot.

## Phase 8 — Keep the fast desktop dotfile loop

- [ ] Keep `homeConfigurations."ammar@ammars-pc"` in `flake.nix`.
- [ ] Keep `hosts/desktop/home.nix` standalone; do not import it into the NixOS configuration.
- [ ] Preserve `nh home switch` as the local command for quick colors, packages, prompts, and other Home Manager changes.
- [ ] Preserve `nh os test`/`nh os switch` for local NixOS experiments.
- [ ] Keep the repo invariant: never use `nix run home-manager -- switch`.
- [ ] Keep the repo invariant: stage new flake-visible files before `nh home switch`.
- [ ] Let local work differ temporarily from released `main`; only committed and merged work is fleet state.

**Done check:** a local Home Manager edit can still be applied immediately without PR, Buildbot, Attic, Comin, or a full NixOS switch.

## Phase 9 — Add activity-aware desktop deployment on Aragorn

- [ ] Add a small deploy controller to `hosts/servers/aragorn/configuration.nix` using existing packages instead of a new external service.
- [ ] Schedule it daily at `04:30` local time.
- [ ] Read Codeberg `main` and pin one exact commit SHA for the full run.
- [ ] Verify that exact SHA has a successful `buildbot/nix-build` Codeberg status before deployment.
- [ ] Keep a lock so two desktop deployments cannot overlap.
- [ ] Keep the last successfully deployed desktop SHA in service state; send Wake-on-LAN only when a newer release is pending.
- [ ] Send the existing Wake-on-LAN packet for `ammars-pc` and wait up to a bounded timeout for LAN SSH.
- [ ] On the desktop, require all safety checks before deployment:
  - [ ] Niri is not running, or `swaylock` is running.
  - [ ] `~/.dotfiles` has no uncommitted or untracked work.
  - [ ] `~/.dotfiles` is on `main`.
  - [ ] The local checkout can fast-forward to the exact released commit; never reset or overwrite local work.
  - [ ] `nix-optimise.service` is inactive.
- [ ] Skip safely when the PC is offline, active, dirty, on another branch, diverged, or still performing maintenance.
- [ ] Deploy the existing `ammars-pc` deploy-rs node from the exact pinned Codeberg revision so `system` activates before `home`.
- [ ] Keep deploy-rs automatic rollback and magic rollback enabled.
- [ ] Keep automatic reboot disabled; report kernel/Nvidia updates that need a supervised reboot.
- [ ] Log success, skip reason, and failure to the systemd journal.
- [ ] Enable node exporter's existing `systemd` collector and add its `textfile` collector on Aragorn; do not add another exporter daemon.
- [ ] Write the desktop controller metrics atomically under `/var/lib/desktop-deploy/metrics/`:
  - [ ] `ammars_pc_deploy_pending`.
  - [ ] `ammars_pc_deploy_pending_since_timestamp_seconds`.
  - [ ] `ammars_pc_deploy_last_attempt_timestamp_seconds`.
  - [ ] `ammars_pc_deploy_last_success_timestamp_seconds`.
  - [ ] `ammars_pc_deploy_result{result="success|woke_success|active|wake_failed|dirty|maintenance|failure"}`.
  - [ ] `ammars_pc_deploy_revision_info{revision="<sha>"}`.
- [ ] Send one ntfy message for every pending-release attempt; send nothing on nights with no pending release.
- [ ] Include the short commit SHA and one result in each message:
  - [ ] `success`: the PC was already reachable and the deploy succeeded.
  - [ ] `woke_success`: the PC was unreachable, Wake-on-LAN succeeded, and the deploy succeeded.
  - [ ] `active`: the PC was reachable but unlocked, so the controller skipped it.
  - [ ] `wake_failed`: the controller sent Wake-on-LAN but SSH never became available.
  - [ ] `dirty` or `maintenance`: local work or Nix maintenance blocked the deploy.
  - [ ] `failure`: deploy-rs started but failed or rolled back.
- [ ] Rate-limit notifications to one final result per nightly attempt so Wake-on-LAN retries do not create message spam.
- [ ] Let a skipped release retry at the next nightly window; keep the manual `deploy .#ammars-pc` path available.

**Done check:** a sleeping, clean desktop wakes and updates; an active or locally modified desktop is untouched; system and Home Manager end on the same released commit.

## Phase 10 — Gate desktop store maintenance on activity

- [ ] Edit `hosts/desktop/configuration.nix` and add one shared maintenance condition.
- [ ] Allow maintenance when Niri is not running or `swaylock` is running.
- [ ] Skip `nix-optimise.service` while Niri is unlocked.
- [ ] Skip `nix-gc.service` while Niri is unlocked.
- [ ] Keep the existing `nix-optimise` window beginning at `03:45`, including its random delay and wake behavior.
- [ ] Keep low CPU and I/O priority as a second layer; do not treat scheduler priority as an activity check.
- [ ] Make the 04:30 desktop deploy wait or skip if optimisation still runs.

**Done check:** neither Nix maintenance nor deployment begins while the desktop session is unlocked.

## Phase 11 — Add deployment monitoring

- [ ] Update `k8s/apps/monitoring/scrapeconfig-infrastructure.yaml` to scrape Comin exporters on port `4243` for enabled hosts.
- [ ] Add `10.30.30.10:4243` as Denethor's Comin target after the OPNsense rule is live.
- [ ] Confirm Prometheus can scrape Denethor while SSH and every non-metrics port remain blocked from the k3s nodes.
- [ ] Add Aragorn to the existing `nixos-node-exporter` scrape targets so Prometheus receives the desktop controller's systemd and textfile metrics.
- [ ] Add Comin alert rules in the existing kube-prometheus configuration for fetch, evaluation, build, and deployment failures.
- [ ] Add an alert for `comin_need_to_reboot`.
- [ ] Add a low-severity alert for a Comin agent that remains suspended unexpectedly.
- [ ] Keep the existing generic failed-systemd-unit alert as the immediate alert for `ammars-pc-deploy.service` failures.
- [ ] Send immediate informational ntfy messages for `success` and `woke_success` so the Wake-on-LAN path is visible.
- [ ] Send immediate warning ntfy messages for `active`, `wake_failed`, `dirty`, and `maintenance` skips.
- [ ] Send an immediate failure ntfy message when deploy-rs fails or rolls back.
- [ ] Add an `ammars-pc` warning when a release remains pending for more than 24 hours.
- [ ] Show the current desktop result, pending age, last successful deployment time, and deployed revision in Prometheus/Grafana queries before adding a dashboard.
- [ ] Route alerts through the existing Alertmanager-to-ntfy path.
- [ ] Verify metrics do not expose repository credentials or secret values; keep `services.comin.debug = false` and expose only commit IDs in revision labels.

**Done check:** a forced harmless Comin failure and a forced harmless desktop-controller failure reach ntfy with the host and failed phase, and recovery clears both alerts.

## Phase 12 — Recovery behavior

- [ ] Keep every existing server deploy-rs node in `flake.nix`.
- [ ] Document that Comin must be suspended before a manual deploy-rs recovery so it does not immediately restore the current Git state.
- [ ] Recover a bad testing deployment by rebooting to `main` or resetting/deleting the testing branch.
- [ ] Recover a bad main deployment by booting a retained generation or deploying a known-good pinned revision with deploy-rs.
- [ ] Fix or revert `main` before resuming Comin.
- [ ] Test recovery with a harmless configuration change; do not simulate a network outage on a critical host.

**Done check:** one documented recovery drill returns a pilot host to a known-good main generation without hand-editing `/nix/var/nix/profiles/system`.

## Phase 13 — Verification and rollout gates

- [ ] Run `nixfmt` on every changed Nix file.
- [ ] Run `nix develop --command pre-commit run --all-files`.
- [ ] Run `nix flake check`.
- [ ] Build the affected host toplevels explicitly during each rollout stage.
- [ ] Run `nh home switch --dry` for the unchanged standalone `ammars-pc` Home Manager output.
- [ ] Confirm Buildbot PR status and Attic upload before every testing-branch merge during the pilot.
- [ ] Check Comin with `comin status`, its systemd journal, and its Prometheus metrics.
- [ ] Check the desktop controller with `systemctl list-timers` and its systemd journal.
- [ ] Perform the first Wake-on-LAN desktop deployment while supervised.
- [ ] Confirm a dirty or unlocked desktop produces a skip and no activation.
- [ ] Confirm no new `.nix` file remains untracked.

**Done check:** local checks pass, CI is green, every enabled host has one automatic deployment owner, and the desktop safety skips are proven.

## Phase 14 — Record the decision

- [x] Create and stage `docs/content/adrs/adr-009-2026-08-19-comin-pull-deployments.md` using the repository MADR format.
- [x] Record the considered choices: Buildbot push deployment, central Aragorn deploy-rs, native timers, Comin everywhere, and the chosen hybrid.
- [x] Record the accepted costs: no Comin automatic rollback, target-side evaluation, one custom desktop activity gate, and deploy-rs retained for recovery.
- [x] Link this plan from the ADR and the ADR from this plan.
- [x] Update the ADR index/navigation files required by `docs/content/adrs/`.

**Done check:** future maintainers can see why servers use Comin while `ammars-pc` keeps standalone Home Manager and activity-aware deploy-rs.

## Expected files

| Path | Action |
|------|--------|
| `flake.nix` | Add Comin input/module wiring; retain deploy-rs nodes and standalone desktop HM |
| `flake.lock` | Lock Comin |
| `modules/nixos/comin.nix` | Create shared Comin service module |
| `modules/nixos/default.nix` | Export the module if required by the existing import pattern |
| `hosts/_profiles/server/configuration.nix` | Enable shared Comin policy after the pilot |
| `hosts/servers/theoden/configuration.nix` | Remove Buildbot deployment; apply any Theoden-specific Comin delay |
| `hosts/servers/denethor/configuration.nix` | Add public Attic and enable Comin |
| `hosts/servers/erebor/configuration.nix` | Enable Comin; retain public Attic |
| `hosts/servers/aragorn/configuration.nix` | Enable Comin and add the desktop deploy controller |
| `hosts/desktop/configuration.nix` | Add activity gates for Nix maintenance |
| `modules/nixos/ssh.nix` | Remove Buildbot fleet key; authorize the scoped Aragorn recovery key |
| `terraform/vlans.tf` | Add the k3s Prometheus scraper alias |
| `terraform/opnsense.tf` | Allow only k3s nodes to Denethor TCP `4243` before the Work VLAN block |
| `k8s/apps/monitoring/scrapeconfig-infrastructure.yaml` | Scrape Comin exporters, including Denethor |
| `k8s/apps/monitoring/helmrelease-kube-prometheus-stack.yaml` | Add Comin alerts in the existing rules section |
| `docs/content/adrs/adr-009-2026-08-19-comin-pull-deployments.md` | Record the architecture decision |

## Risks and controls

| Risk | Control |
|------|---------|
| Comin sees untested `main` | Protect `main`, require `buildbot/nix-build`, and fast-forward the exact green commit |
| Comin and Buildbot duplicate builds | Build PR first, let Attic warm, then merge the same commit to the testing branch |
| Comin has no automatic health rollback | Use testing branches, operation `test`, retained boot entries, alerts, and deploy-rs recovery |
| Main switch partially fails | Alert immediately; boot/deploy a known-good generation and fix Git before resuming Comin |
| Buildbot PR code gains fleet root activation | Remove Buildbot deployment hooks and its fleet key before rollout |
| Desktop update interrupts active work | Require lock/no session, clean main checkout, and inactive store maintenance |
| Desktop local dotfile experiment is overwritten | Skip while the checkout is dirty, non-main, or cannot fast-forward |
| Nvidia update needs reboot | Keep auto reboot off; let failure roll back and alert for supervised reboot |
| Denethor builds locally on 4 GiB | Use public Attic; add Aragorn remote builder only if measured misses require it |
| Denethor monitoring weakens Work VLAN isolation | Allow only the four k3s node IPs to TCP `4243`; keep the blanket block next and verify all other ports stay closed |
| Theoden updates during CI | Observe the pilot; add a Comin confirmation delay only if worker interruption occurs |
| Comin and deploy-rs fight | One automatic owner per host; suspend Comin before recovery deployment |

## Non-goals

- [ ] Do not add Steam Deck deployment in this plan.
- [ ] Do not run Comin and scheduled deploy-rs on the same server.
- [ ] Do not migrate `ammars-pc` to managed/embedded Home Manager.
- [ ] Do not add automatic reboots.
- [ ] Do not add a CI-managed `deploy` branch unless protected-main deployment proves insufficient.
- [ ] Do not add Buildbot testing-branch filters unless measured duplicate work warrants them.
