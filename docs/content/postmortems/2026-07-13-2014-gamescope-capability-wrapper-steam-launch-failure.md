---
date: 2026-07-13
title: Gamescope capability wrapper blocked every Steam game launch
severity: minor
duration: recurring; ~31m focused investigation
systems: [ammars-pc, nixos, steam, gamescope]
tags: [gaming, steam, gamescope, capabilities, pressure-vessel]
commit: https://codeberg.org/ananjiani/infra/commit/50957196
---

## Summary

Every Steam game wrapped with gamescope exited immediately, before the game
launched. Gamescope itself was healthy; Steam's pressure-vessel runtime refused
to execute NixOS's `cap_sys_nice` capability-bearing gamescope wrapper. Setting
`programs.gamescope.capSysNice = false` removed the wrapper capability and
restored gamescope launches.

## Timeline

All times CDT (UTC-5), 2026-07-13.

- **12:58** - Steam recorded an earlier gamescope launch failure with
  `failed to inherit capabilities: Operation not permitted`; the message was
  not identified as causal at the time.
- **19:40** - Reproduced the failure with gamescope HDR launch options. Steam
  stopped tracking the launcher immediately with exit code 1.
- **19:48** - Reproduced with explicit gamescope and Proton logging. The HDR
  toggle completed, but Steam still stopped the game within two seconds.
- **~19:52** - Ran gamescope directly. It initialized successfully; the first
  test only failed because `glxgears` was not installed.
- **~19:54** - Ran a real nested `glxgears` client from a Nix shell. It stayed
  alive until the diagnostic timeout, proving gamescope and nested Xwayland
  were functional.
- **~19:55** - Correlated Steam's console and game-process logs. The earliest
  causal message was `failed to inherit capabilities: Operation not
  permitted`, followed by launcher exit code 1.
- **~19:56** - `getcap /run/wrappers/bin/gamescope` showed
  `cap_setpcap,cap_sys_nice=eip`. Traced it to
  `programs.gamescope.capSysNice = true` in
  `modules/dendritic/gaming.nix`.
- **19:58** - Committed `50957196`, disabling `capSysNice` while retaining
  gamescope and gamemode.
- **20:11** - After `nh os switch`, a gamescope-wrapped Assassin's Creed Black
  Flag Resynced launch succeeded.

## What Happened

NixOS had gamescope enabled with `programs.gamescope.capSysNice = true`. That
option installed `/run/wrappers/bin/gamescope` with `CAP_SYS_NICE` (and wrapper
support capability `CAP_SETPCAP`) so gamescope could request elevated
scheduling priority.

Steam launches Windows games through pressure-vessel. At the boundary between
Steam's launcher and the capability-bearing wrapper, capability inheritance
failed with `EPERM`. The wrapper returned exit code 1 before gamescope or
Proton could start, so Steam showed a brief launch attempt and immediately
returned the game to the stopped state.

The symptom looked like a gamescope crash because no game window appeared and
the process vanished immediately. There was no gamescope coredump because
there was no gamescope crash. HDR flags, Wayland color-management negotiation,
ReShade/RenoDX, Proton, and the game executable were all downstream of the
actual failure.

Disabling `capSysNice` makes Steam execute gamescope as an ordinary
unprivileged program. Gamescope loses elevated scheduler priority, but normal
rendering, nested Xwayland, and HDR operation remain available. Gamemode
continues to provide the configured renicing behavior.

## Contributing Factors

- `programs.gamescope.capSysNice = true` replaced the normal executable path
  with a capability-bearing NixOS security wrapper.
- Steam pressure-vessel rejects or cannot inherit that wrapper's capabilities.
- The user-visible symptom was an instant exit, indistinguishable from an
  application crash without reading Steam's own logs.
- No coredump existed, which initially sent investigation toward gamescope HDR
  flags and Wayland protocol negotiation rather than process startup.
- Steam's `ELFCLASS32` overlay warnings and unrelated HDR negotiation messages
  added noise around the one causal line.
- Gamescope's launch options were being changed while debugging a separate HDR
  issue, making the new flags look causally related.

## What I Was Wrong About

- **"Gamescope crashes immediately."** Gamescope never started in the failing
  path; Steam's launcher failed while entering the capability wrapper.
- **"A missing game window means the renderer or HDR setup failed."** The
  process boundary failed before Proton, DXVK, RenoDX, or HDR initialization.
- **"`capSysNice` is a harmless performance enhancement."** It changes the
  executable's privilege model and therefore its compatibility with sandboxed
  launchers.
- **"The redirected `/tmp/gamescope-ac4.log` will contain the failure."** The
  useful evidence was in Steam's `console-linux.txt` and
  `gameprocess_log.txt`, because failure occurred at Steam's launch boundary.

## What Helped

- Running gamescope independently separated compositor startup from game
  startup.
- A real nested `glxgears` test proved gamescope and Xwayland stayed alive.
- Steam's logs preserved both the exact command and immediate exit code.
- `getcap /run/wrappers/bin/gamescope` connected the error directly to the
  NixOS option.
- The fix was one configuration change and did not require patching gamescope,
  Proton, Steam, or the HDR fork.

## What Could Have Been Worse

- Direct Proton/Wine Wayland launches were unaffected, so games remained
  playable without gamescope.
- No saves, prefixes, or game files were modified while testing.
- If the capability error had been swallowed entirely, investigation could
  have escalated into unnecessary gamescope rebuilds or compositor patches.
- A global workaround that disabled Steam's sandbox would have increased risk
  substantially compared with removing an optional scheduler capability.

## Is This a Pattern?

- [ ] One-off: Correct and move on
- [x] Pattern: Revisit the approach

Capability and setuid wrappers are not transparent performance switches when
the wrapped program is launched through a container or sandbox. Programs
invoked by Steam pressure-vessel should remain unprivileged unless the wrapper
path is explicitly tested. Prefer ordinary execution plus gamemode over
capability-bearing gamescope wrappers on this host.

## Action Items

- [x] Set `programs.gamescope.capSysNice = false` in
      `modules/dendritic/gaming.nix` (`50957196`)
- [x] Apply the NixOS configuration and confirm a gamescope-wrapped Steam game
      launches
- [ ] Add an operational invariant to `AGENTS.md`: do not enable
      `programs.gamescope.capSysNice` for native Steam; pressure-vessel fails
      capability inheritance
- [ ] After HDR behavior is validated, simplify the per-game launch command by
      removing diagnostic logging and any no-longer-needed debug flags

## Lessons

- **An instant exit is not necessarily a crash.** Check whether the target
  executable started before debugging rendering or protocol layers.
- **For Steam launch failures, read `console-linux.txt` and
  `gameprocess_log.txt` before chasing graphics flags.**
- **Check `getcap` when a sandbox reports `Operation not permitted`.**
- **Optional scheduler privileges are not worth breaking the launch path.**
  Unprivileged gamescope plus gamemode is the simpler supported setup here.
