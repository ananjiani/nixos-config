---
date: 2026-07-27
title: Portable Home Manager dev profile + host homelab overlay
status: accepted
supersedes:
superseded_by:
systems: [aragorn, denethor, home-manager, pi, herdr]
tags: [home-manager, profiles, isolation, denethor]
---

## Context and Problem Statement

Aragorn's Home Manager config inlined portable dev tooling (pi, claude-code, Herdr, lang toolchains, headless Stylix) next to homelab-only pieces (sops, tea, Collie/ntfy/mirror plugins, LAN systemd units). Denethor needed the same portable tooling for coding agents but must stay free of every homelab secret, LAN service, Tailscale, and Collie path. Duplicating the portable imports on both hosts would drift; folding Denethor into the shared server profile would import Tailscale, secrets, AdGuard, and k3s by default.

## Decision Drivers

- Keep Aragorn's resulting HM config equivalent (collie/sops/tea/PATH behavior preserved)
- Give Denethor portable agent tooling (including standalone Herdr) without homelab coupling in the activation/generation
- DRY the portable import list — one composition, host overlays only where needed
- Isolation must remain obvious in code review (explicit imports + explicit false gates)

## Considered Options

1. **Flags inside the shared server HM profile** — `modules.dev.enable`, `modules.homelabSecrets.enable`, etc.
2. **Portable `hosts/_profiles/dev/home.nix` + host-local homelab overlay** (chosen)
3. **Duplicate the portable import list on each host** — no shared profile
4. **Accept stale homelab string refs on Denethor** — rejected; finish decoupling instead

## Decision Outcome

Chosen option: **portable dev profile + host overlay + module-level homelab gates**.

`hosts/_profiles/dev/home.nix` imports only portable modules (pi, claude-code, nix-direnv, lang, nix-index, programs/Herdr, headless Stylix). Aragorn imports that profile and layers sops, tea, and Collie/ntfy/mirror on top. Denethor embeds Home Manager itself (without the server profile) and imports essentials + dev only, with:

- `piCodingAgent.searxngUrl = null`
- `piCodingAgent.homelabProviders.enable = false` — empty `models.json` providers; no `/run/secrets` strings; immutable filtered `settings.json` (drops `kimi-coding/`/`zai/`/`opencode-go/` from `enabledModels`; OAuth models stay). `/settings` is repo-managed/immutable there
- `piCodingAgent.homelabExtensions.enable = false` — immutable extensions dir excluding `nvidia-nim.ts` and `usage-tracker.ts`
- `claudeCode.homelabBackends.enable = false` — no claude-kimi/claude-glm fish functions or Tavily/SearXNG/z.ai MCP derivations
- `devPrograms.npmGlobalPackages = null` — npm-global management fully off (no install and no uninstall); do not use `[]` (that still cleans up)
- Git/JJ email is overridden to `ananjiani@dallascollege.edu`; Git credentials use memory-only `cache --timeout=3600` (not plaintext `store`)
- `home-manager.backupFileExtension = "hm-bak"` — first activation renames regular-file clobbers instead of failing
- Claude stable link is HM-managed (`home.file.".local/bin/claude"`), not an activation `rm -f` + `ln -s`

Module defaults stay true so Aragorn/workstations need no extra knobs (full extension/settings out-of-store symlinks, happy-coder npm management, secret providers).

### Consequences

- Good: portable tooling is defined once; shared import set cannot drift
- Good: Denethor's isolation is structural (never imports server/secrets profiles) plus explicit module gates for refs that lived inside portable modules
- Good: npm global install/uninstall is best-effort (`|| echo … >&2`) when non-null; null leaves employer-VM globals alone
- Good: filtered Pi extensions/settings on Denethor cannot re-enable secret-backed models/extensions via shared mutable symlinks
- Bad: Denethor still requires a checkout at `~/.dotfiles` for remaining out-of-store Pi/Herdr paths. Checkout includes encrypted-but-undecryptable secret files and homelab topology docs/config — present on disk, not activated
- Good: Denethor overrides the shared personal Git/JJ email with the Dallas College work address and keeps Git credentials in memory only
- Bad: Denethor has embedded HM activation on `nixos-rebuild`/`deploy`; mis-importing a homelab module would ship secrets or LAN deps (review gate: imports list + false gates + null npm)
- Neutral: standalone `nh home switch` / `homeConfigurations.denethor` remains unsupported — embedded HM only
- Neutral: workstation profile left alone; Stylix interaction is a separate cleanup

### Confirmation

- `nix build .#nixosConfigurations.aragorn.config.system.build.toplevel` succeeds; PATH order restored via `lib.mkAfter` on `~/.npm-global/bin`
- `nix build .#nixosConfigurations.denethor.config.system.build.toplevel` succeeds
- Denethor HM packages include Herdr; denethor eval has no sops/tea/Collie/vault-agent/Tailscale from the new profile
- Denethor extensions exclude `nvidia-nim.ts`/`usage-tracker.ts`; safe settings keep OAuth models only; models providers empty; git helper is `cache --timeout=3600`; no npm global activation
- Denethor generation/closure has no `searxng.lan`, no `/run/secrets` from Pi/Claude homelab backends, no happy-coder management
- Denethor `web-search` exits with a clear not-configured message
- Aragorn defaults still enable full extension/settings symlinks, homelab Claude backends, Pi secret providers, happy-coder npm management, and `https://searxng.lan`

## Pros and Cons of the Options

### Flags inside the shared server HM profile

- Good: one place for all server HM knobs
- Bad: Denethor would still need the server profile (or a fork of it), which pulls Tailscale/secrets/k3s defaults unless every flag defaults off — easy to regress isolation
- Bad: host-name or multi-flag conditionals grow; review must audit defaults, not just imports

### Portable dev profile + host overlay (chosen)

- Good: composition makes the boundary visible — portable imports vs host overlay
- Good: Denethor never loads `hosts/_profiles/server`
- Bad: two HM wiring sites (server profile for fleet, denethor host for work VM) instead of one
- Neutral: module-level gates (`homelabBackends` / `homelabProviders` / `homelabExtensions`) are still flags, but they live next to the refs they hide and default true for existing hosts

### Duplicate portable import list per host

- Good: zero abstraction
- Bad: guaranteed drift between Aragorn and Denethor as modules are added
- Bad: Stylix palette and import set would be copy-pasted

### Accept stale homelab string refs on Denethor

- Good: smaller first diff
- Bad: generation still embeds `searxng.lan` / `/run/secrets` paths; isolation claim is false under inspection
- Bad: rejected in favor of finishing the gates
