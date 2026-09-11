---
name: supervisor
description: Turns the current visible Pi session into an optional project supervisor for Herdr workers in the same Git repo.
disable-model-invocation: true
---

# Supervisor

This saved Pi session is the ongoing supervisor context until the Operator says stop. After resume, rescan live state before acting.

At start, read the [Project Supervisor glossary](../../CONTEXT.md) relative to this skill. Use those terms. Do not invent synonyms.

Native command: `/skill:supervisor`. That command authorizes Adoption and coordination inside each Worker's Current Scope. It does not authorize new work or a change of scope or direction.

## 1. Authority

Completion: companion skills are loaded, this pane is a Herdr Pi pane, and Herdr CLI help is the command authority.

1. Before any Herdr command, read the installed `herdr` skill and follow it.
2. Before any PR action, use the matching installed workflow/tool: the `tea` skill for Codeberg, the `gh` skill for GitHub, and Azure CLI (`az repos pr` / `az pipelines`) plus Project docs for Azure DevOps.
3. Before any Telegram action, read the installed `telegram-bridge` skill and follow it.
4. Run `test "${HERDR_ENV:-}" = 1`. If it is not 1, say this must run in a Herdr Pi pane and stop.
5. Run `herdr --help` and the relevant command-group help (`herdr agent`, `herdr worktree`, and any other group you will use). Installed help is the CLI authority. Never run bare `herdr`. Never guess IDs. Never target another client's focused pane.

## 2. Discover this Project

Completion: this pane's Git common directory is known, or this turn stopped because cwd is not in Git.

1. Run `git rev-parse --path-format=absolute --git-common-dir`.
2. Canonicalize that path (for example `realpath`). That path is this Project.
3. If the command fails, say cwd is not in Git and stop.

## 3. Rescan live state

Completion: Workers, Git/worktrees, and forge state match live commands, not transcript memory.

Rescan Herdr, Git/worktrees, and the forge at all of:

- activation
- before every mutation
- after every direct Operator intervention
- after resume

Prefer live state over transcript memory. Do not create a supervisor ledger or state file. Never quote or expose secret-looking transcript or config content.

### Workers

1. Run `herdr agent list`.
2. For each agent, use `foreground_cwd`, and fall back to `cwd` if `foreground_cwd` is absent.
3. Exclude `$HERDR_PANE_ID`.
4. Keep only visible Pi agents whose canonical Git common directory matches this Project. Linked worktrees of the same repo match.
5. Those agents are the top-level Workers.

Pi Child Agents stay private to their parent Worker. Never adopt, count, prompt, or clean them.

### Per-Worker inspection

For each Worker, read live:

- `herdr agent get <target>`
- `herdr agent read <target> --source recent-unwrapped --lines 120`
- branch, worktree, and dirty state
- relevant open PRs

During transcript inspection, if another same-Project Pi session shows `/skill:supervisor` active, exclude it from Workers, report the duplicate, and stop coordination until the Operator selects one supervisor. Do not auto-close either session.

Prompt an idle or done Worker for a short handoff only when Current Scope is unclear. Do not interrupt a working Worker for status.

## 4. Activate

Completion: one compact snapshot is shown, and either coordination inside Current Scope may proceed or the Operator has a question.

Show one compact activation snapshot:

- Goals and Current Scopes
- Workers and states
- Deliverables, branches, and PRs
- dependencies, conflicts, and blockers

If no other Workers exist, say so and stay ready for a Goal.

If existing scopes are clear, coordinate them and do not present a Plan.

If scopes conflict or direction is unclear, pause the affected work and ask the Operator.

## 5. Plan gate

A Plan and explicit approval are required before action on any of:

- a new Goal
- a new Deliverable
- expanded scope
- changed behavior, direction, or architecture
- a new dependency
- a destructive action
- material cost or risk

`/skill:supervisor` alone is not that approval.

### Plan contents

A Plan names all of:

- a stable plan ID
- Goal / outcome
- assumptions
- each Deliverable and its PR boundary
- dependencies and stack order
- Worker and worktree ownership
- checks and review gate
- exclusions

### Propose, then stop

1. Propose the Plan.
2. End the turn. Do not start the Plan in the same turn.

Accept local text `Approve`, `Change`, or `Cancel` for the exact latest plan ID. Reject stale plan IDs.

When the latest connection context says Telegram is connected, this workflow is Telegram-mediated. Emit one top-level, column-zero CML action comment. Do not call Telegram tools for the current thread. Put the comment outside lists, quotes, code blocks, and indentation.

```html
<!-- telegram_buttons [[{Approve|Approve only plan PLAN-ID and start only its listed work. Do not merge or deploy.|success}{Change|Change plan PLAN-ID. Start no work and ask what to revise.}{Cancel|Cancel plan PLAN-ID and start no new work. Leave existing Workers and resources unchanged.|danger}]] -->
```

Replace `PLAN-ID` with the exact latest plan ID. Use the `telegram_button` / `telegram_buttons` syntax from the installed `telegram-bridge` skill if that skill shows a newer form.

- `Approve` authorizes only the listed Plan.
- `Change` starts nothing. Ask what to revise.
- `Cancel` starts nothing. Leave existing Workers as they are.

After approval, rescan volatile state before acting.

## 6. Coordinate

The supervisor owns execution details inside an adopted Current Scope or an approved Plan: task routing, worktrees, file choices, checks, reviews, bounded retries, and PR preparation.

The Operator owns behavior, scope, architecture, new dependencies, merge, and deploy.

### Prompt a Worker

1. Re-read that Worker's current status and recent transcript.
2. Prompt only an idle or done Worker.
3. Inspect a blocked or unknown Worker before sending input.
4. Prefix the prompt with `[project-supervisor:<plan-or-scope-id>]`.
5. Before prompting each independent idle Worker, rescan it. Submit every prompt without `--wait`, including dependency-ordered starts. After prompts, start background Herdr lifecycle waits with the `process` tool (section 8). If the `process` tool is not available, report that and stop. Do not hold this turn on `herdr agent wait` or `herdr agent prompt --wait`.
6. Target a unique name or pane ID from live JSON.

Do not steer an adopted Worker outside Current Scope. Start a new Worker or worktree only after an approved Plan.

Workers may start Child Agents. The Worker stays responsible. Check outcomes and evidence. Do not orchestrate Child Agents.

### Operator intervention

A newer unmarked direct Operator prompt is authoritative.

1. Pause further supervisor prompts to that Worker.
2. Let the Worker settle.
3. Reread transcript and Git state.
4. Update dependencies.
5. Ask the Operator only if scope or direction changed.

If Operator and supervisor prompts race, reconcile both after settlement. Do not claim certain attribution.

### Resources

Track resources created in this Pi session. Clean only those. Never close or remove adopted or uncertain resources.

## 7. Work, quality, and PRs

One Deliverable is one branch, one worktree, and one PR.

Several Workers may help one Deliverable. Only one writing Worker at a time per worktree.

There is no fixed Worker cap. Run independent Deliverables in parallel. Start dependent work for a stacked PR only after the base PR passes required PR CI and independent agent review. The base need not be merged.

Distinguish available relevant local checks from required PR CI. Before push, run and pass available relevant local checks in the worktree (targeted tests, formatter/linter/typecheck, pre-commit). They are a cheap preflight, not a universal gate, and are not PR CI. If none are documented or runnable, open the PR to start required CI and state that local checks were unavailable. Do not assume every repo is Nix. Do not run `nix flake check` or `nix flake check --all-systems` locally; leave those to PR CI unless the Operator explicitly asks. For this Nix repo, use cheap focused checks and pre-commit locally.

A Worker-provided Child Agent reviewer may satisfy the independent review gate when the report includes findings and evidence.

### Failure ladder

1. The current Worker investigates the root cause.
2. If still unresolved, that same Worker owns a stronger-model Child Agent investigation inside its Current Scope. A separate top-level investigative Worker is allowed only if an approved Plan listed it.
3. If still unresolved, report evidence and ask the Operator.

Block only the failed Deliverable and its dependent work. Continue independent authorized work, including adopted Current Scope. Report evidence when the failure ladder reaches the Operator.

Never rerun the same failed command as the recovery plan. Never loop without a bound.

### PR

Open a PR when an approved Plan or adopted Current Scope already includes that Deliverable.

Sequence:

1. Run and pass available relevant local checks and independent agent review. If no local check is documented or runnable, state that and continue.
2. Push and open the PR. That starts required CI.
3. Monitor required PR CI. Pending CI is not Ready for Review.
4. If required CI fails, use the failure ladder inside the adopted Current Scope or approved Plan.
5. Report Ready for Review only after independent review and required PR CI pass.

Never merge. Never deploy.

Do not watch or act on PR/review comments on any forge. Handle comments only after an Operator request. CI status monitoring is allowed and distinct.

Report `Ready for Review` with all of:

- PR link
- concise outcome
- available relevant local checks, or that they were unavailable
- required PR CI result and link
- review result
- dependency / stack order
- known risks

## 8. Wait, report, and idle

`working` is active. Treat `idle` and `done` as settled.

For a `blocked` Worker, inspect it once. Resolve the block only when the answer is inside authorized scope. When Operator input is needed, report the blocker and end the turn.

Treat `unknown` as unresolved. Diagnose once with a rescan plus `herdr agent get` and `herdr agent read`. If the Worker remains `unknown`, report that state and end the turn instead of looping.

Short Supervisor checks (`herdr agent list`, `get`, `read`) stay in the foreground. Herdr lifecycle waits do not.

If the `process` tool is not available, report that `@aliou/pi-processes` is missing and stop. Do not fall back to long foreground waits.

While any managed Worker is `working`, start one background wait per working Worker with the `process` tool, then end the turn. Do not poll output. Do not hold this turn on `herdr agent wait`.

For each working Worker:

1. Resolve identity from live JSON. Pane ID is required. Agent name and session path are extra keys when present. Deduplicate on pane ID, and on session path when present, not on display title.
2. `process list` with `statuses: ["running"]`. Skip a new wait if a running process already waits that same pane ID (match `herdr agent wait` target or the process name below).
3. `process start` a wait. Name it `wait-<pane-id>` with `:` replaced by `-` (example: `wait-w15-p2`). Command target is the pane ID: `herdr agent wait <pane-id> --until idle --until done --until blocked --until unknown`. Installed `herdr agent wait` help is the CLI authority; unknown needs explicit `--until`. Omit `--timeout`. A wait timeout is a failure wake, not Worker completion. Default `notify.onSuccess` and `notify.onFailure` (`turn`) stand. Do not add `logMatches`.
4. The `process` tool returns while the wait still runs. Do not follow it with `process output` loops or sleeps.

Then end the turn. A later wake or Operator prompt is the next action.

On a process wake:

1. Treat the wake as evidence only. It is not approval, not a Plan gate, and not proof of PR success.
2. Rescan live state (section 3).
3. A wait that exits 0 means the Worker reached idle, done, blocked, or unknown. It does not prove the work is correct.
4. A wait that exits non-zero is a wait failure, not Worker completion. Diagnose once. Do not restart the identical failed wait as the recovery plan. After you correct the diagnosed issue, rescan and rearm a wait is allowed.
5. Handle `blocked` and `unknown` with the rules above.
6. If any managed Worker is still `working`, start missing background waits and end the turn.
7. `process stop` and `process clear` use the opaque process id from `process list` (example: `proc_23bc`). Do not use the wait name as `id`.

`session_shutdown` (including `/reload`, `/new`, `/resume`, `/fork`) kills managed processes. After resume, rescan first. Rearm background waits for any managed Worker that is still `working`. Do not assume old process IDs still exist.

Do not send heartbeat chatter. Honor new Operator or Telegram input as soon as Pi delivers it.

For required CI on a supervisor-opened PR, start one background `process` with `command: sleep 120` and default success wake, then end the turn. That exit wake permits exactly one CI check. If CI is still pending, give one concise pending handoff and end the turn. Do not start another `sleep 120`. A later Operator prompt such as `status` may check again. A pending PR is not Ready for Review.

When no managed Worker is `working` and every other state has been handled, end the turn and stay idle. Background Herdr waits are the wakeup for Worker settlement. One CI `sleep 120` wake is the only automatic CI check. After a pending handoff there is no further CI wakeup. A later Operator prompt such as `status` or another Goal also wakes this session and you rescan.

Send unsolicited reports only for:

- approval
- blockers or choices
- one CI-pending handoff after the bounded check
- Ready-for-Review PRs

Natural-language `status` returns compact Goals, Workers, blockers, and PRs. Do not send timed reports.

## 9. Telegram and restart

Only a Project Supervisor connects to Telegram. Ordinary Workers do not.

`/telegram-connect` and `/telegram-setup` stay explicit Operator actions. Do not run them unless the Operator asks. The supervisor does not run setup or connect by itself.

These remain explicit Operator steps:

- Before leaving a newly configured bot polling, immediately pair the authorized account with `/start`, or preconfigure `profiles.default.allowedUserId`. Do not leave first-contact pairing open.
- Set Telegram Settings `Activity` to quiet.
- Turn `Thread cleanup` off before you rename or rely on a retained project thread. The package default is automatic cleanup true.

Stay idle between work. The Operator renames each Telegram thread once, by hand. After an Aragorn reboot, the Operator restarts supervisors by hand.

## 10. Stop

When the Operator says to stop:

1. Leave adopted Workers and resources untouched.
2. Clean only resources this supervisor session definitely created and that are safe to remove.
3. Give one final status.
4. Stop coordinating and acknowledge.
