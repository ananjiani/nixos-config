---
date: 2026-08-20
title: Optional Project Supervisor agents in Herdr with Telegram
status: accepted
supersedes:
superseded_by:
systems: [pi, herdr, aragorn, telegram, codeberg]
tags: [pi, herdr, agents, telegram]
---

## Context and Problem Statement

Coding work on Aragorn already runs as visible Pi agents inside Herdr, sometimes several in one Git repo. Directing that concurrency from a phone, and adopting agents that were started by hand, is still ad hoc. A parent Pi subagent cannot take over an already-running Herdr session. A custom Telegram bridge would duplicate routing that `@llblab/pi-telegram` already supplies. A headless RPC supervisor would hide the session that local use still needs.

## Decision Drivers

- Gradual opt-in: start with one manual Worker, add a supervisor only when concurrency grows
- Keep top-level Workers visible as ordinary Herdr Pi sessions
- The operator owns behavior, scope, architecture, new dependencies, merges, and deploys
- Reuse Pi's saved session plus Herdr, Git, and Codeberg as source of truth — no supervisor ledger
- Phone access through one dedicated Telegram bot into live Pi instances, not a custom daemon
- Adopt existing Workers; do not require every Worker to be supervisor-spawned

## Considered Options

1. **Pi subagents as top-level Workers**
2. **Herdr Workers plus a custom Telegram bridge using `herdr agent prompt`**
3. **Headless Pi RPC supervisors**
4. **Herdr Workers plus `@llblab/pi-telegram`** (chosen)

## Decision Outcome

Chosen option: **Herdr Workers plus `@llblab/pi-telegram`**, because it keeps every top-level Worker as a normal visible Pi session, can adopt agents started by hand, and reuses a mature Telegram extension instead of a second transport.

One optional Project Supervisor per Git repo, running as a normal visible Pi agent in Herdr on Aragorn. Only visible top-level Herdr Pi agents are the supervisor's Workers. Worktrees isolate Deliverables. `/skill:supervisor` discovers agents in the same repo and worktrees. An operator can begin with one manual Worker and add a supervisor only when concurrency grows.

Existing Workers keep their Current Scope. The supervisor may coordinate inside that scope without a new Plan. A new Goal, or a change of scope or direction, needs a proposed Plan and explicit Approve, Change, or Cancel before new work starts.

The operator owns behavior, scope, architecture, new dependencies, merges, and deploys. The supervisor owns execution details, Worker coordination, checks, retries, and PR preparation. Direct operator prompts to Workers win; the supervisor must resync from the Pi transcript. Workers may start ordinary Pi Child Agents. Those stay private Worker details. The supervisor manages only the top-level Herdr Worker and checks outcomes and evidence.

One Goal can have multiple Deliverables. One Deliverable maps to one branch, worktree, and PR. There is no fixed Worker count. Independent work runs in parallel.

Run and pass available relevant local checks in the worktree before push (targeted tests, formatter/linter/typecheck, pre-commit). They are a cheap preflight, not a universal gate, and are not PR CI. Independent agent review also passes before a PR opens. If no documented or runnable local check exists, open the PR to start required CI and state that local checks were unavailable. Opening the PR starts required CI. Pending CI is not Ready for Review. Check CI once after a 120-second wait; if it remains pending, hand control back to the operator until a later `status` rescan. A CI failure uses the existing failure ladder and blocks only that Deliverable and dependents. Ready for Review requires independent review and required PR CI to pass. Dependent work for a stacked PR may start only after the base PR passes required PR CI and independent agent review. The base need not be merged.

Failure recovery is Worker investigation, then a stronger model, then the operator. The supervisor reports only approval needs, blockers or choices, one CI-pending handoff after the bounded check, and PRs that are Ready for Review. On-demand natural-language `status` gives Goals, Workers, blockers, and PRs. The supervisor does not watch merges or act on Codeberg comments; the operator can ask it to handle comments. CI status monitoring is allowed and distinct. Never merge or deploy. It cleans only Workers and worktrees that it created; adopted ones remain.

Telegram uses one dedicated bot through `@llblab/pi-telegram`, direct into live Pi instances. Private-chat Threaded Mode: one thread per connected supervisor, supervisors only. Rename each generated thread to the project name once, by hand. Keep threads for reconnection. Supervisors stay idle between work and are restarted by hand after an Aragorn reboot. The bot token uses the package's `~/.pi/agent/telegram.json` storage at mode 0600.

Rejected: a custom Telegram daemon, `herdr agent prompt` as Telegram transport, a headless Pi RPC supervisor, a supervisor ledger or state file, and an automatic reboot fleet. Resume uses Pi's saved session and a rescan of Herdr, Git, and Codeberg.

Glossary: `modules/home/dev/pi-coding-agent/CONTEXT.md`.

### Consequences

- Good: Gradual opt-in. Direct/manual and supervised modes coexist.
- Good: No duplicate supervisor state. Source of truth stays Pi, Herdr, Git, and Codeberg.
- Good: One project-level phone thread. Top-level Workers stay visible.
- Bad: `@llblab/pi-telegram` is a third-party security and runtime dependency.
- Bad: Private-thread mode rather than supergroup forums. The extension supports at most 26 live slots.
- Bad: Supervisors are offline after reboot until restarted by hand. Thread names need one manual rename.
- Bad: Same-time operator and supervisor prompts to a Worker can race and need transcript resync.
- Neutral: PR readiness ends supervisor responsibility. Merge and deploy stay manual.

### Confirmation

These checks have not run. Confirm each when the feature exists:

- A repo can run with only a manual Worker. Adding `/skill:supervisor` discovers that Worker and may coordinate inside Current Scope without a new Plan.
- A new Goal or a scope/direction change waits on Approve, Change, or Cancel before new work starts.
- A direct prompt to a Worker takes precedence. The supervisor resyncs from the Pi transcript.
- Child Agents stay private to the Worker. The supervisor manages only the Herdr Worker and checks outcomes and evidence.
- Independent Deliverables run in parallel. Opening a PR starts required CI. Ready for Review waits until that CI passes. Dependent work for a stacked PR may start only after the base PR passes required PR CI and independent agent review. Cleanup removes only Workers and worktrees the supervisor created.

## Pros and Cons of the Options

### Pi subagents as top-level Workers

- Good: Easy parent callbacks and worktree isolation.
- Bad: Cannot adopt manually started visible Herdr agents.
- Bad: Die with the parent, so a supervisor restart drops the whole tree.

### Herdr Workers plus a custom Telegram bridge using `herdr agent prompt`

- Good: Same visible Herdr session model as the chosen option.
- Bad: Duplicates routing, queue, and buttons that `@llblab/pi-telegram` already supplies.
- Bad: Herdr does not expose prompt source identity, so operator vs supervisor prompts are hard to tell apart.

### Headless Pi RPC supervisors

- Good: Structured API for start, prompt, and inspect.
- Bad: No normal visible Pi TUI session for local direct use.

### Herdr Workers plus `@llblab/pi-telegram` (chosen)

- Good: Visible sessions, adoption of hand-started Workers, and phone access without a custom daemon.
- Bad: Depends on a third-party extension with a 26-slot cap, private-thread mode, and manual reboot restart.
