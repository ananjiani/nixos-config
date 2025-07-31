# GitHub Actions Workflows

This directory contains CI/CD workflows for the NixOS dotfiles repository.

## Workflows

### 🚀 CI (ci.yml)
- **Triggers**: Every push and pull request
- **Purpose**: Quick validation of changes
- **Checks**:
  - Flake health check (includes pre-commit hooks)
  - Evaluation of all NixOS configurations
  - Evaluation of all Home Manager configurations
- **Duration**: ~2-3 minutes

### 📅 Weekly Validation (weekly-check.yml)
- **Triggers**: 
  - Every Sunday at 2 AM UTC
  - Manual trigger via GitHub UI
  - All pushes to main/master
- **Features**:
  - Full build test for all hosts
  - Automated flake update PRs
  - Issue creation on build failures
  - Performance metrics
- **Duration**: ~10-15 minutes

## Features

### 🔄 Automated Updates
- Weekly PRs with flake input updates
- Detailed changelogs with commit comparisons
- Auto-assigned to repository owner

### 🚨 Failure Notifications
- Automatic issue creation for build failures
- Detailed error reports with debugging steps
- Prevents duplicate issues

### 💾 Caching
- Uses Magic Nix Cache for fast builds
- No additional Cachix setup required
- Shared cache between workflow runs

## Manual Actions

### Trigger Weekly Check
1. Go to Actions tab
2. Select "Weekly Flake Validation"
3. Click "Run workflow"
4. Choose branch and run

### Skip CI
Add `[skip ci]` to your commit message to skip all workflows.

## Local Testing

Test workflows locally before pushing:
```bash
# Quick check (what CI runs)
nix flake check --all-systems

# Full validation (what weekly runs)
for host in ammars-pc work-laptop framework13 surface-go; do
  nix build .#nixosConfigurations.$host.config.system.build.toplevel --dry-run
done
```