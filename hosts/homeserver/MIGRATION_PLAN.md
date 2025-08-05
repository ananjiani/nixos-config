# Homeserver Migration Plan - Debian to NixOS

## Overview
Migrating homeserver from Debian with Docker Compose to NixOS with native services and SOPS-NIX for secrets management.

## Pre-Migration Checklist

### Hardware Preparation
- [ ] Backup all data from current Debian server
- [ ] Document current storage mount points and partition layout
- [ ] Note down all current service configurations and ports
- [ ] Export all environment variables and secrets from Docker compose files

### NixOS Installation
- [ ] Download NixOS ISO
- [ ] Install NixOS on homeserver
- [ ] Run `nixos-generate-config` to generate hardware-configuration.nix
- [ ] Copy generated hardware-configuration.nix to this directory
- [ ] Ensure storage drives are properly mounted:
  - [ ] `/mnt/storage1` for forgejo, homeassistant, static sites
  - [ ] `/mnt/storage2` for jellyfin, arr-stack data

## Configuration Tasks

### 1. Host Setup
- [x] Create homeserver directory structure
- [x] Create configuration.nix
- [ ] Copy hardware-configuration.nix from newly installed system
- [x] Create home.nix for user environment
- [x] Refactor terminal modules for server/workstation separation
- [x] Create modular profile structure (essentials/workstation)

### 2. SOPS-NIX Setup
- [ ] Generate age key on homeserver: `age-keygen -o /var/lib/sops-nix/key.txt`
- [ ] Add public key to `.sops.yaml` in repository root
- [ ] Create `secrets/homeserver.yaml` with encrypted secrets:
  - [ ] Forgejo admin password
  - [ ] Forgejo runner registration token
  - [ ] Mullvad VPN credentials
  - [ ] Home Assistant secrets
  - [ ] Arr stack API keys
  - [ ] Domain names for services
  - [ ] SSL certificate paths
  - [ ] Service-specific ports (if private)

### 3. Service Modules Creation

#### Forgejo Module (`modules/nixos/services/forgejo.nix`)
- [ ] Configure Forgejo service
- [ ] Set up gitea-actions-runner for CI/CD
- [ ] Configure git SSH access
- [ ] Set up admin user with SOPS secret
- [ ] Configure data directory at `/mnt/storage1/forgejo`

#### Media Services Module (`modules/nixos/services/media.nix`)
- [ ] Configure Jellyfin service
  - [ ] Data directory at `/mnt/storage2/jellyfin/config`
  - [ ] Media directory at `/mnt/storage2/arr-data/media`
- [ ] Configure Radarr service
- [ ] Configure Sonarr service
- [ ] Configure Prowlarr service
- [ ] Configure qBittorrent service

#### Home Assistant Module (`modules/nixos/services/homeassistant.nix`)
- [ ] Configure Home Assistant core service
- [ ] Configure Mosquitto MQTT broker
- [ ] Configure Whisper voice assistant
- [ ] Configure Piper TTS
- [ ] Configure OpenWakeWord
- [ ] Configure ESPHome
- [ ] Configure Matter Server
- [ ] Configure Signal CLI API

#### Reverse Proxy Module (`modules/nixos/services/reverse-proxy.nix`)
- [ ] Configure Nginx as reverse proxy
- [ ] Set up virtual hosts for each service
- [ ] Configure SSL with Let's Encrypt
- [ ] Use SOPS for domain names

#### VPN Module (`modules/nixos/services/vpn-torrents.nix`)
- [ ] Configure WireGuard/OpenVPN for Mullvad
- [ ] Set up network namespace for torrent traffic
- [ ] Route only qBittorrent through VPN
- [ ] Configure kill switch

### 4. Flake Configuration
- [ ] Add homeserver to flake.nix
- [ ] Include all necessary modules
- [ ] Test flake configuration

## Data Migration Steps

### 1. Stop Current Services
- [ ] Stop all Docker containers on Debian server
- [ ] Create final backup of all data

### 2. Copy Data
- [ ] Copy Forgejo data to `/mnt/storage1/forgejo`
- [ ] Copy Home Assistant data to `/mnt/storage1/homeassistant`
- [ ] Copy Jellyfin config to `/mnt/storage2/jellyfin/config`
- [ ] Copy arr-stack configs to `/mnt/storage2/arr-data/config/`
- [ ] Copy media files to `/mnt/storage2/arr-data/media`

### 3. Permission Adjustment
- [ ] Set correct ownership for Forgejo service user
- [ ] Set correct ownership for Jellyfin service user
- [ ] Set correct ownership for Home Assistant service user
- [ ] Set correct ownership for arr-stack service users

## Deployment

### Initial Deployment
- [ ] Run `nixos-rebuild switch --flake .#homeserver`
- [ ] Check for any build errors
- [ ] Verify all services start correctly

### Service Verification
- [ ] Test Forgejo web interface and git operations
- [ ] Test Forgejo runners functionality
- [ ] Test Jellyfin media playback
- [ ] Test Home Assistant dashboard and automations
- [ ] Test arr-stack indexers and downloads
- [ ] Verify VPN is working for torrents only
- [ ] Test all reverse proxy endpoints

### Post-Migration
- [ ] Update DNS records if needed
- [ ] Test external access to services
- [ ] Set up monitoring/alerting
- [ ] Document any custom configurations
- [ ] Create backup strategy for NixOS

## Rollback Plan
- [ ] Keep Debian system backup for at least 1 month
- [ ] Document all configuration changes
- [ ] Test restore procedures

## Notes
- Services to migrate: Forgejo, Jellyfin, Home Assistant, Radarr, Sonarr, Prowlarr, qBittorrent
- Services to skip: Static web servers (obsolete), Foundry VTT (from compose/1)
- All sensitive data managed through SOPS-NIX
- Using native NixOS services instead of Docker where possible

## Module Structure
- `hosts/profiles/essentials/` - Base configuration (core terminal tools, defaults, SOPS)
- `hosts/profiles/workstation/` - Full desktop environment (imports essentials + GUI tools)
- `hosts/homeserver/` - Server configuration (uses essentials + monitoring tools)
- `modules/home/terminal/core.nix` - Essential terminal tools for all systems
- `modules/home/terminal/gui-integration.nix` - Desktop-specific terminal additions
- `modules/home/terminal/monitoring.nix` - System monitoring tools (htop, iotop, ncdu)
- `modules/home/config/defaults.nix` - Universal defaults (NH_FLAKE)
- `modules/home/config/defaults-workstation.nix` - Workstation defaults (EDITOR, MIME types)
