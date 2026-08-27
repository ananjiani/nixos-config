---
date: 2026-08-24
title: One Telegram bot per Project Supervisor host
status: accepted
supersedes: ADR-011
superseded_by:
systems: [pi, herdr, aragorn, denethor, telegram, github, azure-devops, codeberg]
tags: [pi, herdr, agents, telegram]
---

## Context and Problem Statement

ADR-011 placed all Project Supervisors on Aragorn behind one dedicated Telegram bot. Denethor now also runs visible Pi agents for isolated work projects and needs the same phone control. `pi-telegram` permits one `getUpdates` poller per bot token and coordinates followers through host-local IPC, so one token cannot safely serve concurrent Pi organisms on two machines.

Denethor also had repeated out-of-memory kills at 4 GiB. Moving the supervisor there requires more guest memory, while Boromir can release 4 GiB by leaving its idle 3.7 GiB medium Whisper model stopped and using zram for short pressure spikes.

## Decision Drivers

- Run Aragorn and Denethor supervisors at the same time without Telegram polling conflicts
- Keep personal and work host control surfaces isolated
- Reuse the existing Project Supervisor skill and `pi-telegram` instead of building cross-host transport
- Keep every top-level Worker visible in Herdr on its execution host
- Fit supervisor and Worker processes within Denethor's memory budget
- Support each project's actual forge: Codeberg, GitHub, or Azure DevOps

## Considered Options

1. **Share one Telegram bot with manual polling ownership handoffs**
2. **Build or tunnel a cross-host Telegram bus**
3. **Use one dedicated Telegram bot per supervisor host** (chosen)

## Decision Outcome

Chosen option: **one dedicated Telegram bot per supervisor host**, because it preserves `pi-telegram`'s local leader/follower model, lets both hosts run concurrently, and keeps work-host routing separate without new transport code.

Aragorn and Denethor each store their own bot token in that host's `~/.pi/agent/telegram.json` at mode 0600. Each bot uses private-chat Threaded Mode with one thread per connected Project Supervisor. A supervisor coordinates Workers visible through Herdr on its host and continues to follow the authority, planning, review, and cleanup rules from ADR-011.

The supervisor selects the repository workflow from the detected forge: `tea` for Codeberg, `gh` for GitHub, and Azure CLI plus Project documentation for Azure DevOps. It does not watch or act on PR or review comments on any forge without an operator request.

Denethor receives 8 GiB by moving 4 GiB from Boromir. Boromir keeps Wyoming Whisper as a manual fallback, adds zram, and runs at 12 GiB. Start Denethor with one supervisor and one Worker; add more only after live memory evidence shows safe headroom. This is an operating budget, not a fixed supervisor Worker cap.

### Consequences

- Good: Aragorn and Denethor supervisors can stay connected at the same time without competing `getUpdates` pollers.
- Good: Work and personal projects use separate bot tokens, chats, routing state, and host-local IPC.
- Good: The same supervisor skill supports Codeberg, GitHub, and Azure DevOps without a custom forge adapter.
- Bad: The operator must create, pair, configure, and retain one bot per host.
- Bad: There is no single cross-host Telegram thread list; each host has its own bot chat.
- Bad: Denethor concurrency remains memory-sensitive, and Boromir Whisper failover now requires an operator to start the service.
- Neutral: Supervisors still restart by hand after their host reboots.

### Confirmation

- Connect both bots at once and confirm neither reports a Telegram polling conflict.
- Send a prompt to each host's project thread and confirm only the matching Pi instance receives it.
- Run one Denethor supervisor plus one Worker and confirm memory pressure remains healthy without OOM kills.
- Open test PRs from Denethor projects and confirm GitHub uses `gh` and Azure DevOps uses `az`.
- Stop one host's supervisor and confirm the other host's bot remains connected.

## Pros and Cons of the Options

### Share one Telegram bot with manual polling ownership handoffs

- Good: Only one bot token and one private chat to maintain.
- Bad: Only one host can poll safely at a time.
- Bad: A missed disconnect can cause Telegram conflict errors and misrouted expectations.
- Bad: Manual handoffs defeat always-available phone control.

### Build or tunnel a cross-host Telegram bus

- Good: One bot could expose supervisors from both hosts concurrently.
- Good: The operator would keep one aggregate Telegram chat.
- Bad: `pi-telegram` uses local sockets and local process identity; tunneling them is outside its supported boundary.
- Bad: A custom daemon or transport would add authentication, liveness, failover, and routing state that the current design rejects.

### Use one dedicated Telegram bot per supervisor host

- Good: Matches Telegram's one-poller constraint and `pi-telegram`'s host-local bus.
- Good: Failure, restart, and authorization stay isolated by host.
- Good: Requires no new supervisor or Telegram transport code.
- Bad: Adds one-time BotFather and Pi setup for each host.
- Bad: The operator switches between two bot chats for cross-host work.
