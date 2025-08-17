# Homeserver Secrets Setup

## Initial Setup on Homeserver

1. **Generate age key on the homeserver:**
   ```bash
   sudo mkdir -p /var/lib/sops-nix
   sudo age-keygen -o /var/lib/sops-nix/key.txt
   ```

2. **Get the public key:**
   ```bash
   sudo age-keygen -y /var/lib/sops-nix/key.txt
   ```

3. **Update `.sops.yaml`:**
   Replace `age1PLACEHOLDER_REPLACE_WITH_ACTUAL_KEY_AFTER_GENERATION` with the actual public key

## Creating Secrets

1. **Copy the template:**
   ```bash
   cp secrets/homeserver.yaml.template secrets/homeserver.yaml
   ```

2. **Edit with your actual secrets:**
   ```bash
   vim secrets/homeserver.yaml
   ```

3. **Encrypt the file:**
   ```bash
   sops -e -i secrets/homeserver.yaml
   ```

## Extracting Current Secrets from Docker

Extract these from your current Docker compose files:

### Forgejo (compose/25)
- Admin password: Line 17 in docker-compose.yml
- Runner secret: Line 16 & 54

### Mullvad VPN (compose/11)
- OpenVPN user: Line 18

### Arr Stack (compose/11)
- Check existing config files in `/mnt/storage2/arr-data/config/`

### Home Assistant (compose/13)
- Check `/mnt/storage1/homeassistant/config/secrets.yaml`

## Using Secrets in NixOS

Example in a service module:
```nix
{
  config.sops.secrets."forgejo/admin_password" = {
    sopsFile = ../../../secrets/homeserver.yaml;
  };

  services.forgejo = {
    settings.DEFAULT.ADMIN_PASSWORD = config.sops.secrets."forgejo/admin_password".path;
  };
}
```
