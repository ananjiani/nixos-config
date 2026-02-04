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
