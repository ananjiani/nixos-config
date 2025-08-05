# Homeserver Configuration

## Setup Instructions

1. Install NixOS on your homeserver
2. During installation, run `nixos-generate-config` to generate:
   - `hardware-configuration.nix` - Copy this to this directory
   - The generated file will contain your actual:
     - Boot configuration
     - Filesystem mounts
     - Hardware-specific settings

3. Ensure your storage drives are mounted at:
   - `/mnt/storage1` - For forgejo, homeassistant, static sites data
   - `/mnt/storage2` - For jellyfin, arr-stack data

4. Generate age key for SOPS:
   ```bash
   mkdir -p /var/lib/sops-nix
   age-keygen -o /var/lib/sops-nix/key.txt
   ```

5. Add the public key to `.sops.yaml` in the repository root

6. Create and encrypt secrets in `secrets/homeserver.yaml`

7. Deploy with:
   ```bash
   nixos-rebuild switch --flake .#homeserver
   ```
