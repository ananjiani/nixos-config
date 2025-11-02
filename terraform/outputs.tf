output "dns_records" {
  description = "Summary of all DNS records managed by Terraform"
  value = {
    root = {
      name    = cloudflare_record.root.name
      content = cloudflare_record.root.content
      proxied = cloudflare_record.root.proxied
      id      = cloudflare_record.root.id
    }
    git = {
      name    = cloudflare_record.git.hostname
      content = cloudflare_record.git.content
      proxied = cloudflare_record.git.proxied
      id      = cloudflare_record.git.id
    }
    media = {
      name    = cloudflare_record.media.hostname
      content = cloudflare_record.media.content
      proxied = cloudflare_record.media.proxied
      id      = cloudflare_record.media.id
    }
  }
}

output "zone_id" {
  description = "Cloudflare Zone ID"
  value       = local.zone_id
  sensitive   = true
}
