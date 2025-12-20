# NixOS Dotfiles Repository - AI Agent Instructions

This file provides guidance to AI coding assistants when working with code in this repository.

## Repository Overview

This is a NixOS and Home Manager dotfiles repository that manages system configurations for multiple machines using Nix flakes. The codebase follows a modular architecture with clear separation between system-level (NixOS) and user-level (Home Manager) configurations.

### Key Features
- **Modular Configuration**: Reusable modules for common functionality
- **Multi-Host Support**: Configurations for desktop, laptops, and Surface Go
- **Secure Secrets**: SOPS-NIX integration for encrypted credentials
- **Unified Theming**: Consistent colors and styles across applications
- **CI/CD Automation**: GitHub Actions for validation and automated updates
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

## Architecture

### Directory Structure
- **`flake.nix`**: Main entry point defining all system configurations and dependencies
- **`hosts/`**: Machine-specific configurations
  - Each host has: `configuration.nix`, `hardware-configuration.nix`, and `home.nix`
  - Configured hosts: ammars-pc, work-laptop, surface-go, framework13, iso
- **`modules/`**: Reusable configuration modules
  - `home/`: User-level modules (editors, shell, desktop environment)
  - `nixos/`: System-level modules (hardware, services, gaming)
- **`secrets/`**: SOPS-encrypted secrets (keys, tokens)
- **`terraform/`**: OpenTofu/Terraform configs for external infrastructure (Cloudflare DNS, OPNsense firewall)
- **`.github/workflows/`**: CI/CD automation
  - `ci.yml`: Quick validation on every push
  - `weekly-check.yml`: Comprehensive weekly validation with auto-updates

### Key Design Patterns
1. **Modular Configuration**: Features are split into focused modules that can be enabled/disabled per host
2. **Automatic Host Detection**: Home Manager automatically detects hostname and loads appropriate configuration
3. **Hardware Abstraction**: Hardware-specific configurations are isolated in dedicated modules
4. **Secret Management**: Uses SOPS-NIX for encrypted secrets with age keys

### Important Configuration Details
- **Hyprland**: Primary Wayland compositor with extensive customization in `modules/home/desktop/hyprland/`
- **Doom Emacs**: Main editor configuration in `modules/home/editors/doom-emacs/` with custom Doom config
- **Theming**: Uses nix-colors for consistent theming across applications
- **State Version**: NixOS 24.05 (important for compatibility)
- **Laptop Profile**: Common laptop configurations in `modules/home/profiles/laptop.nix`
- **Wallpaper Module**: Centralized wallpaper management in `modules/home/config/wallpaper.nix`
- **Pre-commit Hooks**: Automatic formatting (nixfmt), linting (statix), dead code removal (deadnix), and secret scanning (ripsecrets)
- **CI/CD**: GitHub Actions validate all configurations on push and weekly auto-update flake inputs

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
- **Context and MCP Best Practices**:
  - Use context7 for modular and context-aware Nix configurations
  - Leverage NixOS MCP for advanced system management and deployment strategies
- Do not bypass the precommit hooks

## Important Instructions
- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary for achieving your goal
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested
