# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS and Home Manager dotfiles repository that manages system configurations for multiple machines using Nix flakes. The codebase follows a modular architecture with clear separation between system-level (NixOS) and user-level (Home Manager) configurations.

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

### Key Design Patterns
1. **Modular Configuration**: Features are split into focused modules that can be enabled/disabled per host
2. **Profile System**: Active profile (desktop/laptop/server) is set in `active-profile.nix`
3. **Hardware Abstraction**: Hardware-specific configurations are isolated in dedicated modules
4. **Secret Management**: Uses SOPS-NIX for encrypted secrets with age keys

### Important Configuration Details
- **Hyprland**: Primary Wayland compositor with extensive customization in `modules/home/desktop/hyprland/`
- **Doom Emacs**: Main editor configuration in `modules/home/editors/doom-emacs/` with custom Doom config
- **Theming**: Uses nix-colors for consistent theming across applications
- **State Version**: NixOS 24.05 (important for compatibility)

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
- Any time you make a new file, make sure to stage it
