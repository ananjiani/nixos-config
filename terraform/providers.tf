terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.22"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.12"
    }
  }
}

# SOPS provider — only used for OpenBao root token (bootstrap chicken-and-egg)
provider "sops" {}

data "sops_file" "secrets" {
  source_file = "../secrets/secrets.yaml"
}

# OpenBao (Vault-compatible) provider — must initialize first so other
# providers can read their credentials from OpenBao via data sources.
provider "vault" {
  address = var.openbao_address
  token   = data.sops_file.secrets.data["bao_root_token"]
}

# -----------------------------------------------------------------------------
# Provider credentials stored in OpenBao KV v2
# -----------------------------------------------------------------------------

data "vault_kv_secret_v2" "cloudflare" {
  mount = "secret"
  name  = "k8s/cert-manager"
}

data "vault_kv_secret_v2" "opnsense" {
  mount = "secret"
  name  = "terraform/opnsense"
}

data "vault_kv_secret_v2" "hetzner" {
  mount = "secret"
  name  = "terraform/hetzner"
}

data "vault_kv_secret_v2" "aws" {
  mount = "secret"
  name  = "terraform/aws"
}

data "vault_kv_secret_v2" "proxmox" {
  mount = "secret"
  name  = "terraform/proxmox"
}

data "vault_kv_secret_v2" "mullvad" {
  mount = "secret"
  name  = "terraform/mullvad"
}

data "vault_kv_secret_v2" "cloudflare_zone" {
  mount = "secret"
  name  = "terraform/cloudflare"
}

# -----------------------------------------------------------------------------
# Provider configurations
# -----------------------------------------------------------------------------

provider "cloudflare" {
  api_token = data.vault_kv_secret_v2.cloudflare.data["api-token"]
}

provider "opnsense" {
  uri            = "https://${var.opnsense_host}:8443"
  api_key        = data.vault_kv_secret_v2.opnsense.data["api_key"]
  api_secret     = data.vault_kv_secret_v2.opnsense.data["api_secret"]
  allow_insecure = true # Self-signed cert on fresh install
}

provider "hcloud" {
  token = data.vault_kv_secret_v2.hetzner.data["token"]
}

provider "aws" {
  region     = var.aws_region
  access_key = data.vault_kv_secret_v2.aws.data["access_key_id"]
  secret_key = data.vault_kv_secret_v2.aws.data["secret_access_key"]
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:8006/"
  api_token = data.vault_kv_secret_v2.proxmox.data["api_token"]
  insecure  = true # Self-signed cert

  ssh {
    agent    = true
    username = "root"
  }
}

# Backblaze B2 master key — read from SOPS (same pattern as the vault
# provider's bao_root_token). Keeps the master key out of OpenBao (blast
# radius) while staying reproducible and avoiding per-apply env vars.
# Password manager holds an independent recovery copy.
provider "b2" {
  application_key_id = data.sops_file.secrets.data["b2_master_key_id"]
  application_key    = data.sops_file.secrets.data["b2_master_application_key"]
}
