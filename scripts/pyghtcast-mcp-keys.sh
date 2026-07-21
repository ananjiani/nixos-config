#!/usr/bin/env bash
# Manage the pyghtcast-mcp API-key allowlist in OpenBao.
#
#   ./scripts/pyghtcast-mcp-keys.sh list            # show key prefixes
#   ./scripts/pyghtcast-mcp-keys.sh mint            # generate + add a key, print it once
#   ./scripts/pyghtcast-mcp-keys.sh revoke PREFIX   # remove key(s) matching prefix
#
# Keys live at secret/k8s/pyghtcast-mcp property "api-keys" (comma-separated).
# After any change this syncs the ExternalSecret and restarts the deployment,
# because the pod reads PYGHTCAST_API_KEYS from env at container start.
#
# Requires: sops age key (for the OpenBao token), curl, python3, kubectl.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://100.64.0.21:8200}"
SECRET_PATH="v1/secret/data/k8s/pyghtcast-mcp"
export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/kubeconfig}"

token() {
  sops -d "$REPO_ROOT/secrets/secrets.yaml" | grep '^bao_root_token:' | awk '{print $2}'
}

fetch() { # -> full JSON data object on stdout
  curl -sf "$VAULT_ADDR/$SECRET_PATH" -H "X-Vault-Token: $1" \
    | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["data"]["data"]))'
}

store() { # $1=token, $2=data-json; PUT replaces all properties, so pass everything
  curl -sf -X POST "$VAULT_ADDR/$SECRET_PATH" -H "X-Vault-Token: $1" \
    -d "{\"data\": $2}" >/dev/null
}

resync() {
  kubectl annotate externalsecret pyghtcast-mcp-secrets -n pyghtcast-mcp \
    force-sync="$(date +%s)" --overwrite >/dev/null
  kubectl rollout restart deployment/pyghtcast-mcp -n pyghtcast-mcp >/dev/null
  kubectl rollout status deployment/pyghtcast-mcp -n pyghtcast-mcp --timeout=120s
}

cmd="${1:-list}"
tok="$(token)"
data="$(fetch "$tok")"

case "$cmd" in
  list)
    echo "$data" | python3 -c '
import json,sys
keys = json.load(sys.stdin)["api-keys"].split(",")
for k in keys: print(f"  {k[:8]}…  (len {len(k)})")
print(f"{len(keys)} key(s)")'
    ;;
  mint)
    new="$(openssl rand -hex 32)"
    data="$(echo "$data" | python3 -c "
import json,sys
d = json.load(sys.stdin)
d['api-keys'] = d['api-keys'] + ',' + '$new'
print(json.dumps(d))")"
    store "$tok" "$data"
    resync
    echo
    echo "New key (shown once, hand to the teammate now):"
    echo "  $new"
    ;;
  revoke)
    prefix="${2:?usage: revoke PREFIX}"
    data="$(echo "$data" | python3 -c "
import json,sys
d = json.load(sys.stdin)
keys = [k for k in d['api-keys'].split(',') if not k.startswith('$prefix')]
assert keys, 'refusing to revoke the last key (empty list = server rejects everyone)'
d['api-keys'] = ','.join(keys)
print(json.dumps(d))")"
    store "$tok" "$data"
    resync
    echo "Revoked key(s) with prefix $prefix"
    ;;
  *)
    echo "usage: $0 {list|mint|revoke PREFIX}" >&2
    exit 1
    ;;
esac
