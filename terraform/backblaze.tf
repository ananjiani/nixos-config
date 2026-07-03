# =============================================================================
# Backblaze B2 — Offsite Backup Target
#
# Creates a private B2 bucket for Restic backups and an application key
# with read/write/list/delete. The scoped key is stored in OpenBao under
# secret/nixos/* (host-consumed namespace, allowed by the vault-agent
# policy) so NixOS hosts can retrieve it via vault-agent.
#
# Auth: the B2 *master* key is read by the provider from SOPS
# (see providers.tf). Add b2_master_key_id + b2_master_application_key
# to secrets/secrets.yaml once. Password manager keeps a recovery copy.
# =============================================================================

resource "b2_bucket" "offsite" {
  bucket_name = "ammars-homelab-offsite"
  bucket_type = "allPrivate"

  # Server-side encryption at rest (B2-managed keys). Defense-in-depth on
  # top of restic's client-side encryption; free, no perf cost.
  default_server_side_encryption {
    algorithm = "AES256"
    mode      = "SSE-B2"
  }
}

resource "b2_application_key" "restic" {
  key_name = "restic-backup"
  # listBuckets is required for the S3-compatible API to resolve the bucket
  # name with a bucket-restricted key (restic uses the s3: backend).
  capabilities = [
    "listBuckets",
    "readFiles",
    "writeFiles",
    "deleteFiles",
    "listFiles",
  ]
  bucket_ids = [b2_bucket.offsite.bucket_id]
}

# Write credentials to OpenBao so NixOS hosts can read them via vault-agent
resource "vault_kv_secret_v2" "backblaze" {
  mount = vault_mount.secret.path
  name  = "nixos/backblaze"
  data_json = jsonencode({
    key_id          = b2_application_key.restic.application_key_id
    application_key = b2_application_key.restic.application_key
    bucket_name     = b2_bucket.offsite.bucket_name
  })
}

data "b2_account_info" "current" {}

output "b2_s3_endpoint" {
  description = "S3-compatible API endpoint (restic uses the s3: backend; new B2 keys are v3-API-only, which restic's native b2 backend cannot speak)"
  value       = data.b2_account_info.current.s3_api_url
}

output "b2_bucket_name" {
  description = "Backblaze B2 bucket name for offsite backups"
  value       = b2_bucket.offsite.bucket_name
}
