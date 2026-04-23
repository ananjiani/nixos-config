---
name: bao
description: Interact with OpenBao (Vault-compatible) CLI for secrets management, policy inspection, and vault-agent troubleshooting. Use when the user mentions bao, openbao, vault secrets, consul-template rendering, or vault-agent issues. Also invoke for tasks like reading/writing secrets, checking policies, debugging auth, or inspecting secret paths.
---

# OpenBao CLI Skill

Guide `bao` CLI interactions for this homelab's OpenBao instance on erebor. Covers common workflows, project-specific conventions, and safety rules.

## Environment

- **Address**: `BAO_ADDR=http://100.64.0.21:8200` (set via `.envrc` / direnv)
- **Token**: `VAULT_TOKEN` set via `.envrc` / direnv
- **Server**: OpenBao on erebor (Hetzner VPS), accessed over Tailscale
- **CLI**: `bao` (NOT `vault`). The `openbao` package ships the `bao` binary.
- **MCP server**: vault-mcp-server runs on erebor:8282 for Claude Code integration

## ⚠️ Safety Rules

1. **NEVER print secret values** — only list keys, check structure, or confirm existence
2. **Use `bao kv get -field=<field>` to confirm a field exists** without dumping all fields
3. **Use `bao kv metadata get`** to inspect versioning/ttl without reading data
4. **Prefer `bao kv list`** over `bao kv get` when checking what's available

## Secret Path Conventions

OpenBao uses KV v2 secrets engine mounted at `secret/`. KV v2 paths are prefixed with `data/` for reads/writes and `metadata/` for metadata operations.

| Path pattern | Purpose | Consumer |
|---|---|---|
| `secret/nixos/*` | NixOS host secrets | vault-agent on all hosts |
| `secret/k8s/*` | Kubernetes secrets | External Secrets Operator (ESO) |
| `secret/data/*` | Cross-boundary (shared) | Multiple consumers |

**KV v2 path Gotcha**: `bao kv get secret/nixos/tailscale` auto-prepends `data/`. Raw API calls via `curl` need the full path `secret/data/nixos/tailscale`.

## Common Workflows

### List secrets

```bash
# List all NixOS secrets
bao kv list secret/nixos

# List all k8s secrets
bao kv list secret/k8s

# List everything at root
bao kv list secret/
```

### Read a secret (metadata only — safe)

```bash
# Check what fields exist (does NOT print values)
bao kv get -field=authkey secret/nixos/tailscale
# ^ prints the value — avoid unless you need it

# Safer: just check metadata
bao kv metadata get secret/nixos/tailscale
```

### Write a secret

```bash
# Upsert a field (KV v2 patch — only changes specified fields)
bao kv patch secret/nixos/myservice field=myvalue

# Overwrite entire secret (replaces all fields)
bao kv put secret/nixos/myservice field1=val1 field2=val2
```

### Check policies

```bash
# List all policies
bao policy list

# Read a specific policy
bao policy read vault-agent
bao policy read eso
bao policy read mcp-metadata
```

### AppRole auth

```bash
# List auth methods
bao auth list

# Check AppRole role configuration
bao read auth/approle/role/vault-agent
bao read auth/approle/role/eso

# Get role-id (not a secret)
bao read auth/approle/role/vault-agent/role-id

# Generate a new secret-id (IMPERATIVE — do not put in terraform)
bao write -f auth/approle/role/vault-agent/secret-id
# ^ run this when rotating secret-ids, then update SOPS
```

### Debug vault-agent on a remote host

```bash
# Check if vault-agent service is running
ssh <host> systemctl status vault-agent-default

# Check rendered secrets (existence only, don't cat)
ssh <host> ls -la /run/secrets/

# Check ownership/permissions on a specific secret
ssh <host> stat /run/secrets/tailscale_authkey

# Check vault-agent logs
ssh <host> journalctl -u vault-agent-default -n 50 --no-pager

# Force re-render after sops-nix wiped secrets
ssh <host> systemctl restart vault-agent-default

# Verify rehydration after deploy
ssh <host> ls -la /run/secrets/ && systemctl is-active vault-agent-default
```

### Server health (on erebor)

```bash
# Check OpenBao status
bao status

# Check if sealed
bao operator raft list-peers

# Take a manual Raft snapshot
bao operator raft snapshot save /tmp/manual-backup.snap

# Check Raft storage stats
bao operator raft autopilot state
```

## Architecture Reference

### Policies

| Policy | Purpose | Capabilities |
|---|---|---|
| `vault-agent` | NixOS hosts via vault-agent | Read `secret/data/nixos/*`, plus cross-boundary reads |
| `eso` | External Secrets Operator in k8s | Read `secret/data/k8s/*` |
| `mcp-metadata` | Claude Code MCP server | List metadata, write data (no plaintext reads) |
| `backup` | Daily Raft snapshots | Read `sys/storage/raft/snapshot` |
| `admin` | Human operator (full access) | All capabilities on all paths |

### AppRole Roles

| Role | Policy | Secret ID Management |
|---|---|---|
| `vault-agent` | `vault-agent` | Imperative (SOPS bootstraps role_id + secret_id) |
| `eso` | `eso` | Terraform-managed (has `vault_approle_auth_backend_role_secret_id` resource) |

**CRITICAL**: Never add a `vault_approle_auth_backend_role_secret_id` for vault-agent in terraform. Secret IDs are imperative — terraform would regenerate on every apply and break all hosts. See AGENTS.md "OpenBao / vault-agent" section.

### NixOS Integration

- **Module**: `modules/nixos/vault-agent.nix` — declares secrets as Nix options
- **Profile**: `hosts/_profiles/secrets.nix` — imports vault-agent, bootstraps from SOPS
- **SOPS bootstrap**: `vault_role_id` and `vault_secret_id` are SOPS-encrypted, deposited by sops-nix
- **Rendered secrets**: Written to `/run/secrets/<name>` by Consul Template
- **Ownership**: Enforced by Consul Template `user`/`group` fields (NOT ExecStartPost chown)
- **sops-nix interaction**: sops-nix wipes vault-agent's `/run/secrets/*` on every deploy. `vault-agent-rehydrate` activation script restarts vault-agent after `setupSecrets`.

### Terraform

- **File**: `terraform/openbao.tf`
- **Provider**: `hashicorp/vault` (talks to OpenBao via its Vault-compatible API)
- **Managed**: KV v2 mount, policies, AppRole auth backend, role definitions, secret values bridged from SOPS
- **NOT managed in terraform**: vault-agent secret_id (imperative), AWS KMS credentials (on-disk on erebor)

## Consul Template Syntax

vault-agent uses Consul Template to render secrets. The default template for a field:

```
{{ with secret "secret/data/nixos/tailscale" }}{{ index .Data.data "authkey" }}{{ end }}
```

For multi-line output (e.g., env files), use the `template` option:

```nix
template = ''CF_API_TOKEN={{ with secret "secret/data/k8s/cert-manager" }}{{ index .Data.data "api-token" }}{{ end }}'';
```

Note the `secret/data/` prefix in the Consul Template path — KV v2 requires the `data/` prefix when using the raw secret function. The `bao kv` CLI commands handle this automatically, but Consul Template does not.

## Troubleshooting Cheat Sheet

| Symptom | Check | Fix |
|---|---|---|
| Secret not rendered on host | `ls /run/secrets/` on host | Restart vault-agent: `systemctl restart vault-agent-default` |
| Permission denied on secret | `stat /run/secrets/<name>` | Check `owner`/`group`/`mode` in Nix config |
| vault-agent auth failure | `journalctl -u vault-agent-default` | Check role_id/secret_id in SOPS, re-generate if needed |
| Secret empty after deploy | sops-nix wiped it | `vault-agent-rehydrate` activation script should handle this; verify it ran |
| OpenBao sealed | `bao status` | Check AWS KMS auto-unseal logs on erebor |
| Policy access denied | `bao policy read <policy>` | Verify path patterns include the needed secret |
| ESO can't read secret | Check `eso` policy covers the path | Add path to `eso` policy in `terraform/openbao.tf` |
