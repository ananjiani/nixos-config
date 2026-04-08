#!/usr/bin/env bash
# One-time migration script: seed k8s secrets from SOPS into OpenBao
#
# Prerequisites:
#   - SSH tunnel to erebor: ssh -f -N -L 8200:127.0.0.1:8200 root@91.99.82.115
#   - VAULT_ADDR=http://127.0.0.1:8200
#   - VAULT_TOKEN set (or bao login)
#   - sops and yq installed
#
# Usage: ./scripts/seed-openbao-k8s-secrets.sh

set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

if ! command -v bao &>/dev/null; then
  echo "Error: 'bao' CLI not found. Install openbao or set PATH."
  exit 1
fi

if ! command -v sops &>/dev/null; then
  echo "Error: 'sops' not found."
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "Error: 'yq' not found."
  exit 1
fi

# Test connection
if ! bao status &>/dev/null; then
  echo "Error: Cannot reach OpenBao at $VAULT_ADDR"
  echo "Did you set up the SSH tunnel? ssh -f -N -L 8200:127.0.0.1:8200 root@91.99.82.115"
  exit 1
fi

echo "Connected to OpenBao at $VAULT_ADDR"
echo ""

# Map: openbao_path -> git_path (relative to repo root)
declare -A SECRETS=(
  ["k8s/holmesgpt"]="k8s/apps/holmesgpt/secret.yaml"
  ["k8s/persona-mcp"]="k8s/apps/persona-mcp/secret.yaml"
  ["k8s/renovate"]="k8s/apps/renovate/secret.yaml"
  ["k8s/codeberg-runner"]="k8s/apps/codeberg-runner/secret.yaml"
  ["k8s/zot"]="k8s/apps/zot/secret.yaml"
  ["k8s/opnsense-exporter"]="k8s/apps/opnsense-exporter/secret.yaml"
  ["k8s/cliproxy"]="k8s/apps/cliproxy/secret.yaml"
  ["k8s/stremio"]="k8s/apps/stremio/secret.yaml"
  ["k8s/voicemail-receiver"]="k8s/apps/voicemail-receiver/secret.yaml"
  ["k8s/monitoring"]="k8s/apps/monitoring/home-assistant-secret.yaml"
  ["k8s/forgejo"]="k8s/apps/forgejo/secret.yaml"
  ["k8s/forgejo-runner"]="k8s/apps/forgejo/runner-secret.yaml"
  ["k8s/open-webui"]="k8s/apps/open-webui/secret.yaml"
  ["k8s/homepage"]="k8s/apps/homepage/secret.yaml"
  ["k8s/authentik"]="k8s/apps/authentik/secret.yaml"
  ["k8s/bifrost"]="k8s/apps/bifrost/secret.yaml"
  ["k8s/lobechat"]="k8s/apps/lobechat/secret.yaml"
  ["k8s/cert-manager"]="k8s/infrastructure/controllers/cert-manager-config/cloudflare-secret.yaml"
  ["k8s/k8sgpt"]="k8s/infrastructure/controllers/k8sgpt-config/secret.yaml"
)

FAILED=0
SUCCEEDED=0

for bao_path in "${!SECRETS[@]}"; do
  git_file="${SECRETS[$bao_path]}"
  echo -n "Seeding secret/$bao_path from $git_file ... "

  # Restore file from git to its original path (SOPS needs the path to match .sops.yaml rules)
  git show "HEAD:$git_file" > "$git_file" 2>/dev/null || {
    echo "FAILED (not in git)"
    FAILED=$((FAILED + 1))
    continue
  }

  # Decrypt and extract stringData as JSON
  json=$(sops -d "$git_file" 2>/dev/null | yq '.stringData // .data' -o json 2>/dev/null) || {
    echo "FAILED (decrypt/parse error)"
    rm -f "$git_file"
    FAILED=$((FAILED + 1))
    continue
  }
  rm -f "$git_file"

  # Write to OpenBao
  echo "$json" | bao kv put "secret/$bao_path" - >/dev/null 2>&1 && {
    echo "OK"
    SUCCEEDED=$((SUCCEEDED + 1))
  } || {
    echo "FAILED (bao kv put error)"
    FAILED=$((FAILED + 1))
  }
done

echo ""
echo "Done: $SUCCEEDED succeeded, $FAILED failed (out of ${#SECRETS[@]} total)"

if [ "$FAILED" -gt 0 ]; then
  echo "Some secrets failed — check above for errors."
  exit 1
fi
