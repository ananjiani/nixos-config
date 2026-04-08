# =============================================================================
# OpenBao Configuration (via hashicorp/vault provider)
#
# Provisions the runtime state of the OpenBao secrets manager on erebor:
# - KV v2 secrets engine
# - Policies for vault-agent, ESO, MCP, backup, admin
# - AppRole auth backend with per-host roles
# - Secret values bridged from SOPS (migration layer)
# =============================================================================

# -----------------------------------------------------------------------------
# KV v2 Secrets Engine
# -----------------------------------------------------------------------------

resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv-v2"
  description = "Key-value secrets for NixOS hosts and Kubernetes"
}

# -----------------------------------------------------------------------------
# Policies
# -----------------------------------------------------------------------------

resource "vault_policy" "vault_agent" {
  name   = "vault-agent"
  policy = <<-EOT
    # NixOS hosts read secrets via vault-agent
    path "secret/data/nixos/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/nixos/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "eso" {
  name   = "eso"
  policy = <<-EOT
    # External Secrets Operator for Kubernetes
    path "secret/data/k8s/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/k8s/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "mcp_metadata" {
  name   = "mcp-metadata"
  policy = <<-EOT
    # Claude Code MCP — list structure and write, but no plaintext read
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
    path "secret/data/*" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "backup" {
  name   = "backup"
  policy = <<-EOT
    # Daily Raft snapshot backup
    path "sys/storage/raft/snapshot" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_policy" "admin" {
  name   = "admin"
  policy = <<-EOT
    # Full access for human operators
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

# -----------------------------------------------------------------------------
# AppRole Auth Backend
# -----------------------------------------------------------------------------

resource "vault_auth_backend" "approle" {
  type = "approle"
}

# Per-host roles — each NixOS server gets its own AppRole identity
locals {
  approle_hosts = {
    boromir   = ["vault-agent"]
    samwise   = ["vault-agent"]
    theoden   = ["vault-agent"]
    rivendell = ["vault-agent"]
    erebor    = ["vault-agent"]
  }
}

resource "vault_approle_auth_backend_role" "hosts" {
  for_each = local.approle_hosts

  backend        = vault_auth_backend.approle.path
  role_name      = each.key
  token_policies = each.value
  # 24h token TTL, renewable up to 7 days
  token_ttl     = 86400
  token_max_ttl = 604800
}

# Generate a secret_id for each host (used during vault-agent bootstrap)
resource "vault_approle_auth_backend_role_secret_id" "hosts" {
  for_each = local.approle_hosts

  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.hosts[each.key].role_name
}

# ESO (External Secrets Operator) — separate role with "eso" policy for k8s secrets
resource "vault_approle_auth_backend_role" "eso" {
  backend        = vault_auth_backend.approle.path
  role_name      = "eso"
  token_policies = ["eso"]
  token_ttl      = 86400  # 24h
  token_max_ttl  = 604800 # 7d
}

resource "vault_approle_auth_backend_role_secret_id" "eso" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.eso.role_name
}

# -----------------------------------------------------------------------------
# Secret Values — bridged from SOPS into OpenBao KV v2
#
# Only secrets that are ALSO consumed directly via SOPS on hosts that don't
# use vault-agent (desktop, framework13, erebor, rivendell).
# Secrets consumed exclusively via vault-agent live only in OpenBao.
# -----------------------------------------------------------------------------

resource "vault_kv_secret_v2" "tailscale" {
  mount = vault_mount.secret.path
  name  = "nixos/tailscale"
  data_json = jsonencode({
    authkey = data.sops_file.secrets.data["tailscale_authkey"]
  })
}

resource "vault_kv_secret_v2" "k3s" {
  mount = vault_mount.secret.path
  name  = "nixos/k3s"
  data_json = jsonencode({
    token = data.sops_file.secrets.data["k3s_token"]
  })
}

resource "vault_kv_secret_v2" "trakt" {
  mount = vault_mount.secret.path
  name  = "nixos/trakt"
  data_json = jsonencode({
    client_id     = data.sops_file.secrets.data["trakt_client_id"]
    client_secret = data.sops_file.secrets.data["trakt_client_secret"]
  })
}
