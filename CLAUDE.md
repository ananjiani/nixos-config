# NixOS Dotfiles Repository - AI Agent Instructions

This file provides guidance to AI coding assistants when working with code in this repository.

## Repository Overview

This is a NixOS and Home Manager dotfiles repository that manages system configurations for multiple machines using Nix flakes. The codebase follows a modular architecture with clear separation between system-level (NixOS) and user-level (Home Manager) configurations.

### Key Features
- **Modular Configuration**: Reusable modules for common functionality
- **Multi-Host Support**: Configurations for desktop, laptops, and Surface Go
- **Secure Secrets**: SOPS-NIX integration for encrypted credentials
- **Unified Theming**: Consistent colors and styles across applications
- **CI/CD Automation**: Buildbot-nix on Theoden with Attic binary cache
- **Pre-commit Hooks**: Automatic formatting and linting with git-hooks.nix
- **Dendritic Modules**: Aspect-oriented configuration using flake-parts and import-tree in `modules/dendritic/`

## ⚠️ CRITICAL: New Files Must Be Git-Staged

**Nix flakes only see git-tracked files.** Always run `git add <file>` immediately after creating any new `.nix` file, otherwise Nix will not see it and you'll get "option does not exist" or "module not found" errors.

## Common Commands

### System Rebuild (using nh)
```bash
# Apply NixOS system configuration
nh os switch

# Test build without applying changes (dry run)
nh os switch --dry

# Test configuration without switching
nh os test
```

### Home Manager (using nh)
```bash
# Apply Home Manager configuration for current user
nh home switch

# Test build without applying changes (dry run)
nh home switch --dry
```

### Development Commands
```bash
# Search for packages
nh search <package-name>

# Format Nix files
nixfmt <file.nix>

# Check flake
nix flake check

# Update flake inputs
nix flake update

# Show flake metadata
nix flake metadata

# Run pre-commit hooks manually
nix develop --command pre-commit run --all-files

# Enter development shell with pre-commit hooks
nix develop
```

### ISO Build
```bash
# Build the live USB / installation ISO
nix build .#nixosConfigurations.iso.config.system.build.isoImage

# The ISO will be at result/iso/nixos-*.iso
```

### CI/CD Commands
```bash
# Test what CI will run locally
nix flake check --all-systems
```

### Codeberg CLI (berg)
Use berg instead of gh since this repo is on codeberg.
```bash
berg --help
```

### Remote Deployment (using deploy-rs)
```bash
# Enter devshell to get deploy command
nix develop

# Deploy to all servers (boromir, samwise, theoden)
deploy .

# Deploy to specific server
deploy .#boromir
deploy .#samwise
deploy .#theoden

# Skip magic rollback (auto-confirm)
deploy .#boromir -- --confirm

# Build on remote instead of locally
deploy .#boromir --remote-build
```

**Magic Rollback**: By default, deploy-rs waits 240 seconds for confirmation. If not confirmed (or SSH drops), the system automatically reverts to the previous configuration.

### Ansible (Proxmox Host Management)
```bash
# Enter devshell to get ansible
nix develop

# Test connectivity to all Proxmox hosts
ansible -i ansible/inventory/hosts.yml proxmox -m ping

# Dry run (show what would change)
cd ansible && ansible-playbook playbooks/site.yml --check --diff

# Apply to all hosts
cd ansible && ansible-playbook playbooks/site.yml

# Apply only to specific host
cd ansible && ansible-playbook playbooks/site.yml --limit rohan

# Run only GPU fan control role (rohan only)
cd ansible && ansible-playbook playbooks/proxmox-gpu.yml
```

**Ansible manages Proxmox hosts** (not NixOS VMs):
- **rohan** (192.168.1.24) - Has NVIDIA 1070 Ti
- **gondor** (192.168.1.20)
- **the-shire** (192.168.1.23)

**Roles:**
- `proxmox-base`: SSH hardening, base packages, authorized keys
- `proxmox-monitoring`: node_exporter (port 9100), smartd
- `nvidia-fan-control`: NVIDIA driver + coolgpus fan control (rohan only)

**Note:** The nvidia-fan-control role pins kernel 6.14 because 6.17 lacks headers for DKMS builds. Renovate monitors NVIDIA driver releases to notify when newer drivers support newer kernels.

## Architecture

### Directory Structure
- **`flake.nix`**: Main entry point defining all system configurations and dependencies
- **`hosts/`**: Machine-specific configurations
  - Each host has: `configuration.nix`, `hardware-configuration.nix`, and `home.nix`
  - Local machines: ammars-pc, framework13
  - Servers (Proxmox VMs): boromir, samwise, theoden (deployed via deploy-rs)
  - Special: iso
- **`modules/`**: Reusable configuration modules
  - `home/`: User-level modules (editors, shell, desktop environment)
  - `nixos/`: System-level modules (hardware, services, gaming)
- **`secrets/`**: SOPS-encrypted secrets (keys, tokens)
- **`terraform/`**: OpenTofu/Terraform configs for external infrastructure (Cloudflare DNS, OPNsense firewall)
- **`k8s/`**: Kubernetes manifests for k3s cluster (managed by Flux)
- **`ansible/`**: Ansible playbooks and roles for Proxmox host management

### Key Design Patterns
1. **Modular Configuration**: Features are split into focused modules that can be enabled/disabled per host
2. **Automatic Host Detection**: Home Manager automatically detects hostname and loads appropriate configuration
3. **Hardware Abstraction**: Hardware-specific configurations are isolated in dedicated modules
4. **Secret Management**: Uses SOPS-NIX for encrypted secrets with age keys

### Important Configuration Details
- **Hyprland**: Primary Wayland compositor with extensive customization in `modules/home/desktop/hyprland/`
- **Doom Emacs**: Main editor configuration in `modules/home/editors/doom-emacs/` with custom Doom config
- **Theming**: Uses Stylix for consistent color theming across applications (migrated from nix-colors 2026-04-11; `nix-colors` input removed). Base16 scheme: `gruvbox-material-dark-soft`. Config in `modules/dendritic/desktop/default.nix`.
- **State Version**: `23.05` (workstations), `25.11` (servers) — must stay separate, do not unify.
- **Laptop Profile**: Common laptop configurations in `modules/home/profiles/laptop.nix`
- **Wallpaper Module**: Centralized wallpaper management in `modules/home/config/wallpaper.nix`
- **Pre-commit Hooks**: Automatic formatting (nixfmt), linting (statix), dead code removal (deadnix), and secret scanning (ripsecrets)
- **CI/CD**: Buildbot-nix validates all configurations on push, caches builds to Attic binary cache

### Repository & CI
- **Primary**: Codeberg (https://codeberg.org/ananjiani/infra)
- **Mirror**: GitHub (auto-synced via Codeberg push mirror)
- **CI**: Buildbot-nix at https://ci.dimensiondoor.xyz
- **Binary Cache**: Attic at theoden.lan:8080 (middle-earth cache)

## Working with This Repository

### Adding New Modules
1. Create module file in appropriate directory (`modules/home/` or `modules/nixos/`)
2. Import it in the respective `default.nix`
3. Enable it in host configuration with options

### Modifying Host Configurations
- Host-specific settings go in `hosts/<hostname>/configuration.nix` or `home.nix`
- Hardware settings stay in `hardware-configuration.nix` (usually generated)
- Use existing modules when possible rather than direct configuration

### Managing Secrets
- Secrets are encrypted with SOPS using age keys
- Edit with: `sops secrets/secrets.yaml`
- Age key location: `~/.config/sops/age/keys.txt`

### Common Development Patterns
- When modifying Hyprland config: Check `modules/home/desktop/hyprland/hyprland.nix`
- For editor configs: Look in `modules/home/editors/`
- System services: Check `modules/nixos/services/`
- Gaming-related: See `modules/nixos/gaming/`
- Laptop-specific: Use `modules/home/profiles/laptop.nix`
- Wallpaper settings: Configure via `wallpaper` option in host home.nix
- Any time you make a new file, make sure to stage it

### Best Practices
- Import shared modules rather than duplicating configuration
- Use options for configurable modules (see wallpaper.nix example)
- Keep host-specific config minimal, leverage modules
- Document module options and their purpose
- Do not bypass the precommit hooks

## Important Instructions
- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary for achieving your goal
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested

## Operational Invariants

Load-bearing repo gotchas — each is a hard-won lesson that silently breaks things if ignored, usually learned in production and not derivable from the code alone. If you find yourself doing one of these "wrong", assume someone tried it once and it broke something.

### Nix patterns

- **Statix single-block key assignment**: use `services = { greetd = ...; pipewire = ...; }`, NOT separate `services.greetd` and `services.pipewire` lines. Pre-commit rejects the flat form.
- **Closure tracking for flake-relative paths**: passing `../../foo.json` to a setting that serializes (YAML/JSON) — DO NOT use `toString <path>`. The string appears in the config but `nix-store -q --references` returns empty, and the file doesn't ship on deploy. Fix: `pkgs.writeText "name" (builtins.readFile cfg.path)` OR `builtins.path { path = <abs>; name = "foo"; }` with an ABSOLUTE path. Silently bit `services.headscale.settings.policy.path` on 2026-04-20; the pattern at `modules/nixos/headscale.nix` is the canonical fix.
- **NEVER `nix run home-manager -- switch`**: it builds from its own flake (not the repo's) and produces a broken generation with almost no packages. Always `nh home switch`.
- **File clobbering on `nh home switch`** (standalone HM — no `backupFileExtension`): before switching, manually `mv` any files HM reports would be clobbered (common repeaters: `~/.mozilla/firefox/profiles.ini`, `~/.config/atuin/config.toml`, `~/.local/share/applications/mimeapps.list`, `~/.pi/agent/settings.json`).

### Tooling

- Use `tofu` (OpenTofu, devshell ships 1.11.5), NOT `terraform`.
- Use `bao` (OpenBao), NOT `vault` — repo ships openbao. `BAO_ADDR=http://100.64.0.21:8200` and `VAULT_TOKEN` both come from direnv.
- Use `berg` (Codeberg CLI), NOT `gh` — Codeberg is primary; GitHub is a push mirror only.
- NEVER print secret values — only list keys or check structure.

### OpenBao / vault-agent

- **One AppRole for all hosts** reads `secret/data/nixos/*`. Don't add per-host AppRoles — the aspirational `for_each` design was dead code, removed 2026-04-10.
- **Secret IDs are imperative**, NOT in terraform. Terraform declares the role only; `hosts/_profiles/secrets.nix` reads `vault_role_id` + `vault_secret_id` from SOPS. A `vault_approle_auth_backend_role_secret_id` resource would regenerate the secret_id on every apply and break every host.
- **Secret ownership via Consul Template `user`/`group` template fields**, NOT `systemd ExecStartPost` chown. ExecStartPost fires once; Consul Template re-renders on every lease renewal (~1h) and would overwrite ownership back to `root:root 0400` each time. Symptom of regression: `/run/secrets/<name>` readable right after deploy, root-owned ~1h later with no config change.
- **sops-nix wipes vault-agent's `/run/secrets/*` on every `switch-to-configuration`** — it sees files not in its manifest as "stale" and removes them. `system.activationScripts.vault-agent-rehydrate` in `modules/nixos/vault-agent.nix` restarts vault-agent after `setupSecrets` to force a re-render. Without this, every deploy silently degrades services consuming vault-agent secrets until the first lease renewal (~1h).
- **Multi-line secret templates** (e.g. `CF_API_TOKEN=<value>` env-file format): use the secret submodule's `template` field for verbatim rendering instead of the default `{{ .Data.data.<field> }}`. See `hosts/servers/erebor/configuration.nix` for the Caddy Cloudflare token example.
- **Rivendell uses SOPS for all secrets** (no vault-agent) because it has no Tailscale and can't reach OpenBao over the LAN.

### Networking & DNS

- **`networking.nameservers` must be LAN-only by default** (base.nix). Public fallback poisons systemd-resolved's Global scope: when the LAN resolver goes unhealthy, resolved picks the public one, `*.dimensiondoor.xyz` gets NXDOMAIN instead of the AdGuard split-DNS rewrite. Erebor is the only exception (VPS with no LAN).
- **`privacy.mullvadCustomDns` must be LAN-only**, never a public fallback. Mullvad filters LAN servers out of `wg0-mullvad` when ANY tunnel-reachable entry exists, leaving only the public one, which then catches `~.` and routes all DNS externally.
- **Mullvad tailscale-bypass needs BOTH nftables marks**: `ct mark 0x00000f41` AND `meta mark 0x6d6f6c65`. Only one of the two is a silent drop. See `systemd.services.mullvad-tailscale-bypass` in `hosts/desktop/configuration.nix`.
- **`ts.dimensiondoor.xyz`** points to erebor's public IPv4 (`91.99.82.115`) post-2026-04-20 Headscale migration. No AdGuard split-DNS rewrite — LAN clients go via public DNS so a logged-out node can reach Headscale.

### Hardware

- **Tailscale is PERMANENTLY disabled on rivendell.** Its r8169 NIC has two bugs: hardware offloading causes RX buffer overflow at ~7 min (fix via ethtool), and Tailscale's netfilter modifications trigger a driver bug causing complete inbound loss at ~11 min. The r8168 OOT driver is broken on kernel ≥ 6.13; the `eee_enable` modprobe param is r8168-only and not valid for r8169.
- **Tailscale `useExitNode` defaults to `"boromir"`** — servers should set `useExitNode = null` unless they actually need an exit node.

### deploy-rs

- **Multi-target fails** (`deploy .#a .#b`). Use `deploy .` (no target) for all hosts in parallel, or a single target. `--skip-checks` bypasses unrelated flake check failures.
- **Boromir**: ComfyUI podman container crashes on activation, causing deploy-rs to fail. Force through with `--auto-rollback false --magic-rollback false`.
- **Cold-boot chicken-and-egg**: if tailscaled-autoconnect times out during activation, magic rollback fires. Workaround: build closure locally, `nix copy --to ssh://root@host`, then `nix-env -p /nix/var/nix/profiles/system --set <path> && <path>/bin/switch-to-configuration switch`.

### k3s

- **IPVS + NixOS firewall**: pod → ClusterIP traffic arrives on the INPUT chain via `cni0` and gets dropped by `nixos-fw` before IPVS can intercept. Fix is the `iptables -I nixos-fw 1 -i cni0 -s 10.42.0.0/16 -d 10.43.0.0/16 -j nixos-fw-accept` rule in `modules/nixos/server/k3s.nix`'s `networking.firewall.extraCommands`.
- **Flannel + keepalived VIP corruption**: flannel picks up keepalived VIPs (52–56) as its public-ip, corrupting host-gw routes cluster-wide. `--flannel-iface` alone is NOT sufficient; must also `--flannel-external-ip` + `--node-external-ip=<nodeIp>` so the CCM sets the `flannel.alpha.coreos.com/public-ip-overwrite` annotation. Setting that annotation manually is ignored — it has to go through the CCM.
- **Dual-stack IPv6 for pods is BLOCKED**: the single-stack → dual-stack migration crashes flannel (k3s-io/k3s#10726, nil pointer in `WriteSubnetFile`). Migration would require deleting ALL node objects and restarting simultaneously. Don't attempt.
- **Post-flannel-change ritual**: restart ALL Longhorn instance-managers + CSI sidecars (attacher/provisioner/resizer/snapshotter). Stale pods inherit old IPs and break DNS/connectivity silently.
- **Flux `GitRepository.spec.depth` does NOT exist** in source-controller v1 API (v1.7.4). Only the archive `ignore` filter is available.

### Bifrost (LLM Gateway)

- **Virtual keys MUST be declared in the HelmRelease** `governance.virtualKeys` with `value: "env.VAR_NAME"`. Dashboard-only keys are lost on PVC recreation.
- **Anthropic endpoint translation is broken for z.ai / DeepSeek** (v1.3.0+): Bifrost's `/anthropic/v1/messages` unconditionally translates to OpenAI **Responses API** (`/v1/responses`), not Chat Completions. Only `cliproxy` works as a flexible passthrough. Upstream fix in PR #2599.
- **zai provider needs explicit `models:` whitelist** per key (coding-PaaS tier quirk). Other providers forward any model string unchanged.
- **open-webui's `zai/glm-4.7` facade actually routes to DeepSeek** via an initContainer in `k8s/apps/open-webui/deployment.yaml` (`base_model_id = "deepseek/deepseek-chat"`). The UI label does not match the backend — don't trust the label when debugging.

### HolmesGPT

- At `https://holmes.lan` (self-signed — use `curl -sk`). API field is `ask`, NOT `question`: `POST /api/chat {"ask": "...", "model": "bifrost-kimi"}`. Helm service: `holmesgpt-holmes:80` → container `5050`.
