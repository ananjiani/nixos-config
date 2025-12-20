terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.16"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

# SOPS provider for reading encrypted secrets
provider "sops" {}

# Data source to read secrets from SOPS-encrypted file
data "sops_file" "secrets" {
  source_file = "../secrets/secrets.yaml"
}

# Cloudflare provider configuration
provider "cloudflare" {
  api_token = data.sops_file.secrets.data["cloudflare_api_token"]
}

# OPNsense provider configuration
provider "opnsense" {
  uri            = "https://${var.opnsense_host}"
  api_key        = data.sops_file.secrets.data["opnsense_api_key"]
  api_secret     = data.sops_file.secrets.data["opnsense_api_secret"]
  allow_insecure = true # Self-signed cert on fresh install
}
