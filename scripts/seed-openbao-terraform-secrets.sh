#!/usr/bin/env bash
# One-time script: seed Terraform provider credentials from SOPS into OpenBao.
# Run from the repo root with an active OpenBao session (VAULT_ADDR + VAULT_TOKEN).
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8200  # via SSH tunnel
#   export VAULT_TOKEN=$(sops -d --extract '["bao_root_token"]' secrets/secrets.yaml)
#   bash scripts/seed-openbao-terraform-secrets.sh

set -euo pipefail

SECRETS_FILE="secrets/secrets.yaml"

decrypt() {
  sops -d --extract "[\"$1\"]" "$SECRETS_FILE"
}

echo "=== Seeding Terraform provider credentials into OpenBao ==="

# Cloudflare zone_id (api-token already exists at k8s/cert-manager)
echo "[1/5] terraform/cloudflare"
bao kv put secret/terraform/cloudflare \
  zone_id="$(decrypt cloudflare_zone_id)"

# OPNsense
echo "[2/5] terraform/opnsense"
bao kv put secret/terraform/opnsense \
  api_key="$(decrypt opnsense_api_key)" \
  api_secret="$(decrypt opnsense_api_secret)"

# Hetzner
echo "[3/5] terraform/hetzner"
bao kv put secret/terraform/hetzner \
  token="$(decrypt hcloud_token)"

# AWS (KMS auto-unseal)
echo "[4/5] terraform/aws"
bao kv put secret/terraform/aws \
  access_key_id="$(decrypt aws_access_key_id)" \
  secret_access_key="$(decrypt aws_secret_access_key)"

# Proxmox
echo "[5/5] terraform/proxmox"
bao kv put secret/terraform/proxmox \
  api_token="$(decrypt proxmox_api_token)"

# Mullvad VPN
echo "[6/5] terraform/mullvad"
bao kv put secret/terraform/mullvad \
  server_pubkey="$(decrypt mullvad_server_pubkey)" \
  server="$(decrypt mullvad_server)" \
  private_key="$(decrypt mullvad_private_key)" \
  public_key="$(decrypt mullvad_public_key)" \
  address="$(decrypt mullvad_address)"

echo ""
echo "=== Done! Verify with: bao kv list secret/terraform ==="
echo ""
echo "You can now remove these keys from secrets/secrets.yaml:"
echo "  cloudflare_api_token, cloudflare_zone_id,"
echo "  opnsense_api_key, opnsense_api_secret,"
echo "  hcloud_token, aws_access_key_id, aws_secret_access_key,"
echo "  proxmox_api_token,"
echo "  mullvad_server_pubkey, mullvad_server, mullvad_private_key,"
echo "  mullvad_public_key, mullvad_address"
