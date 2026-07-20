# Doom Emacs → nix-doom-emacs-unstraightened Migration

**Date**: 2026-07-20
**Status**: Deployed on ammars-pc — state migrated and smoke tests passed; framework13 + stability window pending
**Decision**: documented in `docs/content/adrs/adr-005-2026-07-20-doom-emacs-unstraightened.md`

## Summary

Replace the imperative Doom Emacs setup (activation-time `git clone` + `doom sync` in `modules/dendritic/doom-emacs.nix`) with [nix-doom-emacs-unstraightened](https://github.com/marienz/nix-doom-emacs-unstraightened): Doom core, modules, and all elisp packages built by Nix; DOOMDIR wired as a flake input pointing at `github:ananjiani/doom-emacs`. Migrates ammars-pc and framework13; **Doom is disabled on pixel9 entirely** (unused there). The legacy imperative code is deleted outright — no dual code path.

## Scope decisions (settled)

- **pixel9**: drop Doom Emacs (`doom-emacs.enable` removed from `hosts/pixel9/home.nix`) — unused; sidesteps the aarch64 build/cache question and removes the need for a legacy code branch
- **DOOMDIR wiring**: dedicated flake input `github:ananjiani/doom-emacs` (submodules are invisible to flake path sources — repo-relative `./modules/home/editors/doom-emacs` would evaluate near-empty)
- **Profile**: keep Unstraightened's default `nix` profile and migrate state files; do NOT use the `profileName = ""` escape hatch (upstream calls it a hack)
- **Submodule fate**: **drop it** — flake.lock becomes the single pin. Timing: keep during the migration window (it is the rollback path for the imperative setup), remove in Phase 6 cleanup; local editing moves to a standalone clone (e.g. `~/src/doom-emacs`)

## Phase 1 — Flake wiring

1. `flake.nix`: add inputs:
   ```nix
   doom-config = {
     url = "github:ananjiani/doom-emacs";
     flake = false;
   };
   nix-doom-emacs-unstraightened = {
     url = "github:marienz/nix-doom-emacs-unstraightened";
     inputs.doomdir.follows = "doom-config";
     inputs.nixpkgs.follows = "";  # per upstream README, reduces downloads
   };
   ```
2. Add the upstream Cachix cache to `nix.settings` in `hosts/_profiles/base.nix` (alongside the existing nix-community/hyprland entries):
   - substituter: `https://doom-emacs-unstraightened.cachix.org`
   - trusted-public-key: `doom-emacs-unstraightened.cachix.org-1:O5oOlRPnmQEvVaFyuMTmthCEooHbrg54WgSLR07tmg4=`
   (Verified live from the Cachix API 2026-07-20.) Note this lands via `nh os switch` (system-level nix.settings), so do the OS switch before the first Doom build or the cache won't be consulted.
3. `nix flake lock` and verify eval.
4. If package export reports unsupported `unpin` metadata, remove the matching `unpin!` declaration from DOOMDIR. This migration removed `(unpin! org-roam)` so Unstraightened can preserve Doom's org-roam pin.

**Done check**: `nix flake metadata` shows both inputs; `doom-config` locked to the current submodule HEAD (`78bb871` at time of writing — re-check when implementing; push any unpushed submodule commits first).

## Phase 2 — Rewrite `modules/dendritic/doom-emacs.nix`

Keep the aspect's option surface (`doom-emacs.enable`, `variant`, `service.enable`, `secrets.enable`) so host configs don't change. Internally:

1. Import Unstraightened's `homeModule` into the aspect's homeManager config (needs access to the flake input inside the dendritic module — same pattern other dendritic modules use for inputs).
2. Replace `programs.emacs` + activation hooks with:
   ```nix
   programs.doom-emacs = {
     enable = true;
     emacs = if cfg.variant == "pgtk" then pkgs.emacs-pgtk else pkgs.emacs-nox;
     extraPackages = epkgs: [ epkgs.treesit-grammars.with-all-grammars ];
     # doomDir follows the doom-config input by default
     # provideEmacs = true (default) → installs `emacs`/`emacsclient` like emacsWithDoom
   };
   ```
3. `services.emacs`: Unstraightened sets itself as `services.emacs.package`; keep `service.enable` gating and the existing `Unit.After = [ "graphical-session.target" ]` fix for pgtk.
4. **Delete**: `activation.installDoomEmacs`, `activation.doomSync`, the `autoSync` option, `DOOMDIR` and `sessionPath = [ "$HOME/.emacs.d/bin" ]` session vars.
5. **Keep**: Doom runtime deps in `home.packages` (fd, ripgrep, nodejs, prettier, mermaid-cli, aspell dicts), shell aliases, and `secrets.enable` SOPS decryption hook. Drop `TREESIT_GRAMMAR_PATH`; bundled `extraPackages` owns tree-sitter grammar discovery.
6. **pixel9**: remove the `doom-emacs = { ... }` block from `hosts/pixel9/home.nix` (drop, not migrate). The nox variant support in the module can stay — it is one line and harmless.
7. `git add` everything; run pre-commit (nixfmt/statix/deadnix will flag the deleted code).

**Done check**: `nh home switch --dry` builds the full Doom closure for the workstation config with no activation git/network steps in the plan.

## Phase 3 — DOOMDIR config adjustments (in ananjiani/doom-emacs repo)

1. When `:term ghostel` is enabled, set `ghostel-module-directory` to a writable path (`~/.local/share/ghostel/`) because its package directory is read-only in the store.
2. Audit found one stale `~/.emacs.d` path in `.mcp.json`. Its MCP package is disabled, so defer the path change until MCP is re-enabled; no active config writes into DOOMDIR. `custom.el` remains manually maintained because its store copy is read-only.
3. `vterm-shell "fish"` etc. unaffected; vterm now comes from Unstraightened's package set instead of `epkgs.vterm` — config unchanged.
4. Push; update `doom-config` lock entry.

**Done check**: no active DOOMDIR config writes; the disabled MCP path is explicitly deferred.

## Phase 4 — First switch on ammars-pc

1. Stop the Emacs daemon.
2. `nh home switch` (watch for HM clobber warnings per repo invariant — `mv` anything it would overwrite).
3. State migration (one-time, per machine):
   ```
   ~/.emacs.d/.local/etc/   → ~/.local/share/doom/nix/
   ~/.emacs.d/.local/state/ → ~/.local/state/doom/nix/
   ```
   Verify org-roam DB, recentf, savehist, bookmarks arrive. Caches (`.local/cache`) are disposable.
4. Keep `~/.emacs.d` (old checkout + packages) untouched until confidence — it is the rollback path. Note: binary `emacs` now comes from the Unstraightened wrapper; the old checkout is inert without `DOOMDIR`/`doom sync`.
5. Restart daemon; smoke test: org-roam, magit, vterm, agenda views, gptel, evil everywhere.
6. `doom doctor` via the wrapped binary — expect the documented benign warnings (non-standard location, "another Emacs config").

**Done check**: daily-driver session on ammars-pc for a few days with no missing state or packages.

## Phase 5 — framework13 + CI

1. `nh home switch` on framework13 (pull from Attic/Cachix — confirm no local mass-rebuild).
2. Drift confirmation: `nix path-info` of the Doom derivation identical on both machines.
3. Buildbot: confirm `nix flake check --all-systems` tolerates the IFD. If it fails, options in order of preference: enable `experimentalFetchTree` (upstream-suggested), allow IFD in the buildbot nix settings, or exclude the HM configs from the check and rely on build jobs.
4. Confirm Attic caches the closure.

**Done check**: CI green; both workstations on identical closure.

## Phase 6 — Cleanup + follow-ups (separate pass, after stability window)

- Remove the DOOMDIR submodule: `git submodule deinit modules/home/editors/doom-emacs`, `git rm` the path, drop the `.gitmodules` entry. Clone `ananjiani/doom-emacs` to a standalone working copy (e.g. `~/src/doom-emacs`) for config editing.
- `rm -rf ~/.emacs.d` on migrated machines once rollback confidence is established (destructive — operator action, not automated).
- Fix `.mcp.json`'s stale `~/.emacs.d` path before re-enabling its currently disabled MCP package.
- New-config workflow documentation: edit loop is now *commit/push → `nix flake update doom-config` → `nh home switch` → `systemctl --user restart emacs`*; for experiments, evaluate elisp live or use `nh home switch -- --override-input doom-config path:<local doom-emacs checkout>`.

## Rollback

Any phase before cleanup: `git revert` the dotfiles commits + `nh home switch` restores the imperative module; `~/.emacs.d` and its synced packages are still on disk, `DOOMDIR` env returns, daemon restarts on the old stack. State files moved in Phase 4 must be moved back (or symlinked forward from the start if extra caution is wanted).

## Risks

| Risk | Mitigation |
|------|------------|
| Unpinned-package build breakage (pins-can-break class) | Upstream CI gates its Doom/emacs-overlay pins; for our own `packages.el` pins, add `:recipe`/`emacsPackageOverrides` as documented |
| IFD breaks buildbot check | Phase 5 step 3 options; worst case exclude HM eval from `flake check` |
| First build very slow | Cachix + Attic; build on desktop first, laptop pulls |
| Doom needed on pixel9 later | Re-enable requires verifying aarch64 builds via buildbot/Attic first (noted in ADR) |
| State migration misses a file | Old `~/.emacs.d/.local` retained until cleanup phase |
| Emacs daemon env regressions (Wayland clipboard) | `graphical-session.target` ordering is preserved in the rewrite |
