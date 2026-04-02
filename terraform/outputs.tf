output "dns_records" {
  description = "Summary of all DNS records managed by Terraform"
  value = {
    root = {
      name    = cloudflare_dns_record.root.name
      content = cloudflare_dns_record.root.content
      proxied = cloudflare_dns_record.root.proxied
      id      = cloudflare_dns_record.root.id
    }
    git = {
      name    = cloudflare_dns_record.git.name
      content = cloudflare_dns_record.git.content
      proxied = cloudflare_dns_record.git.proxied
      id      = cloudflare_dns_record.git.id
    }
    media = {
      name    = cloudflare_dns_record.media.name
      content = cloudflare_dns_record.media.content
      proxied = cloudflare_dns_record.media.proxied
      id      = cloudflare_dns_record.media.id
    }
    sji_api = {
      name    = cloudflare_dns_record.sji_api.name
      content = cloudflare_dns_record.sji_api.content
      proxied = cloudflare_dns_record.sji_api.proxied
      id      = cloudflare_dns_record.sji_api.id
    }
  }
}

output "zone_id" {
  description = "Cloudflare Zone ID"
  value       = local.zone_id
  sensitive   = true
}

# =============================================================================
# Hetzner Cloud
# =============================================================================

output "erebor_ipv4" {
  description = "Erebor VPS public IPv4 address"
  value       = hcloud_server.erebor.ipv4_address
}

output "erebor_ipv6" {
  description = "Erebor VPS public IPv6 network"
  value       = hcloud_server.erebor.ipv6_network
}

output "erebor_ssh" {
  description = "SSH command to connect to erebor"
  value       = "ssh root@${hcloud_server.erebor.ipv4_address}"
}

# =============================================================================
# OpenBao
# =============================================================================

output "approle_role_ids" {
  description = "AppRole role IDs for each NixOS host (place in /var/lib/vault-agent/role-id)"
  value       = { for k, v in vault_approle_auth_backend_role.hosts : k => v.role_id }
}

output "approle_secret_ids" {
  description = "AppRole secret IDs for each NixOS host (place in /var/lib/vault-agent/secret-id)"
  value       = { for k, v in vault_approle_auth_backend_role_secret_id.hosts : k => v.secret_id }
  sensitive   = true
}
