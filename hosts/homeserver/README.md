# Homeserver Configuration

This configuration sets up a NixOS homeserver with the following services:

## Services

- **Forgejo**: Git forge with CI/CD runners
- **Jellyfin**: Media server
- **Arr Stack**: Radarr, Sonarr, Prowlarr for media management
- **qBittorrent**: Torrent client with VPN isolation
- **Home Assistant**: Smart home automation with voice assistants
- **Nginx**: Reverse proxy for all services

## Setup Instructions

### 1. Install NixOS on your homeserver

### 2. Generate hardware configuration:
```bash
sudo nixos-generate-config
```
Copy the generated `/etc/nixos/hardware-configuration.nix` to this directory.

### 3. Configure secrets:

For testing (unencrypted):
- Copy `homeserver-secrets.yaml` from the repo root to the homeserver
- Fill in all actual values (domains, passwords, Mullvad config, etc.)
- This file is gitignored and should NEVER be committed!

For production (encrypted with SOPS):
```bash
# Generate age key
mkdir -p /var/lib/sops-nix
age-keygen -o /var/lib/sops-nix/key.txt

# Add the public key to .sops.yaml in repo root
# Encrypt the secrets file
sops -e homeserver-secrets.yaml > secrets/homeserver.yaml
```

### 4. Ensure storage is mounted:
- `/mnt/storage1` - For Forgejo data
- `/mnt/storage2` - For media files, Home Assistant, arr stack

### 5. Deploy:
```bash
sudo nixos-rebuild switch --flake .#homeserver
```

### 6. Post-installation setup:
- Set Forgejo admin password
- Configure arr stack API keys in each service
- Complete Home Assistant onboarding
- Import your Mullvad WireGuard configuration

## Network Layout

- All services run behind Nginx reverse proxy with SSL (Let's Encrypt)
- qBittorrent runs in isolated VPN namespace (only torrent traffic goes through VPN)
- Services are accessible at:
  - `https://git.yourdomain.com` - Forgejo
  - `https://media.yourdomain.com` - Jellyfin
  - `https://home.yourdomain.com` - Home Assistant
  - `https://radarr.yourdomain.com` - Radarr
  - `https://sonarr.yourdomain.com` - Sonarr
  - `https://prowlarr.yourdomain.com` - Prowlarr
  - `http://homeserver:8118` - qBittorrent (local only)

## Security Notes

- All external services use HTTPS with valid certificates
- qBittorrent traffic is isolated through VPN with kill switch
- Secrets are managed via unencrypted YAML for testing (migrate to SOPS for production)
- Firewall only allows ports 22 (SSH), 80/443 (HTTP/HTTPS), and configured service ports

## Maintenance

Update the system:
```bash
nix flake update
sudo nixos-rebuild switch --flake .#homeserver
```

View logs:
```bash
journalctl -u forgejo
journalctl -u jellyfin
journalctl -u home-assistant
journalctl -u qbittorrent
```

Add new services by creating modules in `modules/nixos/services/`
