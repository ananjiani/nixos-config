---
name: nix-repo-conventions
description: Repository-specific conventions for this NixOS dotfiles repo. Load when creating, modifying, or enabling Nix modules, editing host configurations, or working with flake-parts/import-tree. Proactively invoke when the user asks to add a feature, create a module, or modify system/home configuration.
---

# NixOS Dotfiles Repository Conventions

This repository manages NixOS systems and Home Manager configurations using multiple module patterns. Choosing the wrong pattern is the most common mistake.

## Three Module Systems

This repo uses **three different module systems** in parallel. Picking the right one matters:

### 1. Traditional NixOS modules (`modules/nixos/`)

For system-level services, hardware, kernel modules, firewall rules, systemd units.

- Shape: `{ config, pkgs, lib, ... }: { options = { ... }; config = { ... }; }`
- Import: add to `modules/nixos/default.nix` exports (or host `configuration.nix` directly)
- Enable per-host: set `myModule.enable = true` in the host's `configuration.nix`

**Example:** `modules/nixos/services/headscale.nix`, `modules/nixos/gaming/`

### 2. Traditional Home Manager modules (`modules/home/`)

For user-level dotfiles, desktop apps, shell config, editor config.

- Shape: `{ config, pkgs, lib, ... }: { options = { ... }; config = { ... }; }`
- Import: add to `modules/home/default.nix`
- Enable per-host: set in host's `home.nix` (or detected automatically by hostname)

**Example:** `modules/home/dev/pi-coding-agent.nix`, `modules/home/editors/`

### 3. Dendritic modules (`modules/dendritic/`)

For aspect-oriented, cross-cutting features using `flake-parts` + `import-tree`.

- Shape: `{ inputs, ... }: { flake.modules.<class>.<aspect> = { ... }; }`
- Auto-loaded by `import-tree` — **no manual import needed**
- Enable per-host: import the aspect in `flake.nix` or host config
- Files/directories prefixed with `_` are ignored by `import-tree`

**Example:** `modules/dendritic/desktop/default.nix` (theming), `modules/dendritic/crypto.nix`

## Decision Flow: Which System?

```
Does it need systemd services, kernel modules, or firewall rules?
  → modules/nixos/

Is it user-level (dotfiles, apps, shell/editor config)?
  → modules/home/

Does it span both system and user configuration (aspect-oriented)?
  → modules/dendritic/
```

When in doubt, use `modules/nixos/` or `modules/home/` — dendritic is reserved for cross-cutting concerns that naturally split across `nixos` + `homeManager` + `darwin` classes.

## Adding a New Traditional Module

1. Create the file in `modules/nixos/` or `modules/home/`
2. Use the options + config pattern:

```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.myModule;
in
{
  options.myModule = {
    enable = lib.mkEnableOption "my module";
    # add other options here
  };

  config = lib.mkIf cfg.enable {
    # implementation
  };
}
```

3. Export it in the respective `default.nix`
4. Enable it in the host's `configuration.nix` or `home.nix`
5. **Stage the file**: `git add` it immediately (Nix flakes only see git-tracked files)

## Adding a New Dendritic Aspect

1. Create a file in `modules/dendritic/` named after the feature
2. Define `flake.modules.nixos.<aspect>` and/or `flake.modules.homeManager.<aspect>`
3. Use `import-tree` conventions:
   - One aspect per file (usually)
   - Share values via `let`-bindings, NOT `specialArgs`
   - Use `lib.mkEnableOption` for configurability
4. No manual import needed — `import-tree` auto-discovers it
5. **Stage the file**: `git add` it immediately

## Host Configuration Patterns

- Each host directory: `hosts/<hostname>/`
- Files: `configuration.nix` (system), `home.nix` (user), `hardware-configuration.nix` (hardware)
- Hosts: `ammars-pc`, `framework13` (workstations); `boromir`, `samwise`, `theoden` (servers); `iso` (live USB)
- State versions: `23.05` for workstations, `25.11` for servers — **must stay separate, never unify**
- Home Manager auto-detects hostname and loads appropriate config

## Verification Workflow

After making Nix changes, verify before committing:

```bash
# Fast local check (current system only)
nix flake check

# Full CI parity check (all systems — slow, builds everything)
nix flake check --all-systems
```

**`nix flake check` includes pre-commit hooks** (nixfmt, statix, deadnix, ripsecrets) as part of its checks. Running it catches eval errors AND formatting/linting issues in one go.

For **quick hook-only feedback** without full eval:
```bash
nix develop --command pre-commit run --all-files
```

## Common Pitfalls

- **Forgetting to `git add` new `.nix` files**: Nix flakes are blind to untracked files. Always stage immediately after creation.
- **Using `toString <path>` for serializable configs**: Use `pkgs.writeText` or `builtins.path { path = <abs>; name = "foo"; }` with absolute paths instead. See `modules/nixos/headscale.nix` for the canonical fix.
- **Mixing dendritic and traditional patterns**: Don't put `flake.modules.*` in `modules/nixos/` or `modules/home/`. Don't put traditional modules in `modules/dendritic/`.
- **Wrong state version**: Workstations use `23.05`, servers use `25.11`. Do not unify.
