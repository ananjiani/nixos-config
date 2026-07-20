---
date: 2026-07-20
title: Manage Doom Emacs declaratively with nix-doom-emacs-unstraightened
status: accepted
supersedes:
superseded_by:
systems: [doom-emacs, home-manager, buildbot, attic, ammars-pc, framework13, pixel9]
tags: [emacs, home-manager, reproducibility, dendritic]
---

## Context and Problem Statement

Doom Emacs is currently managed by a self-described hack in `modules/dendritic/doom-emacs.nix`: a Home Manager activation script clones `doomemacs` into `~/.emacs.d` once (shallow, single-branch, never updated), and a second activation script runs `doom sync` on every `nh home switch`. The DOOMDIR is a git submodule (`github.com/ananjiani/doom-emacs`) referenced by absolute path via the `DOOMDIR` environment variable. This worked, but has accumulated real problems:

1. **Drift between machines.** Each host froze `~/.emacs.d` at whatever commit it happened to clone. Desktop, framework13, and pixel9 run different Doom revisions with no record of which.
2. **Upgrades are imperative and interactive.** `doom upgrade` prompts, rebases a git checkout in place, and its outcome is not captured anywhere in the repo. The 2026-07 upgrade (needed for the new `:term ghostel` module) crossed Doom's 2.1 restructuring — the repo was renamed to `doomemacs/core` with the module tree split into a git submodule — and had to be shepherded by hand.
3. **Package installs float.** Doom pins most package revs in-tree, but unpinned packages resolve at whatever time each machine happens to sync, adding a second source of drift.

The trigger for deciding now: the manual Doom 2.1 upgrade made the cost of the imperative approach concrete, and the operator explicitly weighted cross-machine drift as the deciding factor.

## Decision Drivers

- Eliminate Doom-version and package drift between ammars-pc, framework13, and pixel9
- Upgrades must be non-interactive, recorded in the repo, and revertible
- Doom config iteration speed matters — the DOOMDIR sees frequent tweaks (long history of `chore(doom): bump` commits)
- Single operator; prefer deleting imperative activation machinery over hardening it
- CI (buildbot-nix) and binary cache (Attic) already exist and should be able to validate/cache the editor
- pixel9 is aarch64 with limited build capacity (AVF VM on a phone)

## Considered Options

1. **Status quo** — keep the clone-once + `doom sync` activation hack
2. **Pin the Doom core rev in the dendritic module** — activation fetches/checks out a declared sha, `doom sync --force` converges; upgrades become "bump the sha"
3. **nix-doom-emacs-unstraightened** — build Doom and all packages with Nix; DOOMDIR becomes a flake input; delete the activation hack entirely

## Decision Outcome

Chosen option: **nix-doom-emacs-unstraightened**, because it is the only option that eliminates both drift axes (Doom version *and* package set) — the operator's stated priority — and it converts upgrades into ordinary `nix flake update` + generation rollback, validated by existing CI. Option 2 was seriously considered and is strictly cheaper, but it leaves package installs floating and keeps failures at activation time on the target machine rather than at build time in CI.

Two scope calls made alongside the main decision: **Doom is dropped from pixel9 entirely** (it was unused there, and this avoids both the aarch64 build/cache question and any need to keep the legacy imperative code path alive), and **the DOOMDIR git submodule will be removed** once the migration proves out — the flake input (`github:ananjiani/doom-emacs`) becomes the single pin, avoiding a decorative second pin that would drift from `flake.lock`. The submodule is retained during the migration window only as the rollback path.

Unstraightened is the community-canonical successor: the archived `nix-community/nix-doom-emacs` points to it, the NixOS wiki recommends it, and its CI gates its pinned Doom/emacs-overlay inputs so a broken upstream bump cannot reach consumers. It already tracks the Doom 2.1 `doomemacs/core` + modules-submodule split.

### Consequences

- Good: every host on the same flake rev runs a bit-identical Doom closure; drift is structurally impossible
- Good: upgrades are `nix flake update <input>` + switch; rollback is a Home Manager generation switch (seconds, exact)
- Good: editor build failures surface in buildbot before any machine switches; Attic can serve the built closure to other hosts
- Good: the activation hack (git clone, `doom sync`, `autoSync` option) is deleted, not hardened
- Bad: the DOOMDIR is copied into the store read-only — the config edit loop changes from "edit + `doom/reload`" (sub-second, in-place) to "commit/push + update lock + `nh home switch` + restart the Emacs daemon". This is a daily-felt ergonomic tax accepted in exchange for reproducibility
- Bad: `custom-file` saving breaks (read-only store path); Custom changes must be applied to the repo manually
- Bad: Unstraightened's pin-application is a documented hack; user-added `package!` pins can fail at build time (missing commits, dropped deps) and need `:recipe` or `emacsPackageOverrides` workarounds
- Bad: IFD (import-from-derivation) enters flake evaluation; may need accommodation in `nix flake check --all-systems` / buildbot
- Neutral: Doom state paths move to XDG locations under the `nix` profile (`~/.cache/doom/nix`, `~/.local/share/doom/nix`, `~/.local/state/doom/nix`); one-time migration of `~/.emacs.d/.local/{etc,state}`
- Neutral: pixel9 loses Doom Emacs (unused there); re-enabling later means verifying aarch64 build/cache viability first
- Neutral: Doom config editing moves out of the `.dotfiles` workspace once the submodule is removed (separate `ananjiani/doom-emacs` checkout)

### Confirmation

- `nix path-info` on the Doom derivation matches across ammars-pc and framework13 at the same flake rev
- `home.activation` contains no `installDoomEmacs`/`doomSync` entries on migrated hosts
- A config tweak lands on both workstations via push + lock update + switch, with no `doom sync` run anywhere
- Buildbot builds the Doom closure and CI stays green for two weeks; one deliberate rollback via generation switch succeeds

## Pros and Cons of the Options

### Status quo (imperative clone + doom sync)

- Good: zero migration cost; edit loop is optimal (`doom/reload`)
- Good: no new inputs, no IFD, nothing for CI to choke on
- Bad: drift between machines is unbounded and unrecorded — the problem that prompted this decision
- Bad: upgrades are interactive, in-place, and unrecoverable except by hand
- Bad: activation does network I/O and mutates `~/.emacs.d`; failures happen mid-switch on the target machine

### Pin the Doom core rev in the dendritic module

- Good: ~10-line diff; edit loop unchanged; upgrades become non-interactive sha bumps recorded in git
- Good: kills Doom-version drift and the interactive-upgrade problem; idempotent no-op when the rev matches
- Neutral: forecloses nothing — would have been deleted along with the rest of the hack if Unstraightened came later
- Bad: unpinned packages still float at install time; package-set drift between machines persists (the operator's stated priority)
- Bad: `doom sync` still runs at activation — failures surface on the target machine, not in CI; rollback is revert + re-sync (minutes, approximate), not a generation switch
- Bad: `~/.emacs.d/.local` remains mutable machine-local state; nothing is cacheable or CI-validated

### nix-doom-emacs-unstraightened

- Good: full closure reproducibility; both drift axes eliminated; store-backed instant rollback
- Good: build-time failure surfacing via existing buildbot + Attic infrastructure; Cachix available upstream (x86_64)
- Good: upstream is actively maintained, CI-gated, and already handles the Doom 2.1 core/modules split
- Neutral: DOOMDIR must be reachable as flake source — as a git submodule it is invisible to flakes by default, so it is wired as a dedicated flake input (`github:ananjiani/doom-emacs`) rather than a repo-relative path
- Bad: read-only DOOMDIR changes the daily edit loop (rebuild + daemon restart per persisted tweak)
- Bad: IFD slows evaluation and may complicate CI; aarch64 cache coverage uncertain (moot for now — Doom dropped from pixel9, the only aarch64 host)
- Bad: known sharp edges: `custom.el` saving, state-path migration, pins-can-break for user packages, ghostel's native module needs a writable `ghostel-module-directory`
