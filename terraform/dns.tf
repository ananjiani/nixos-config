# Get the zone ID from SOPS secrets
locals {
  zone_id = data.sops_file.secrets.data["cloudflare_zone_id"]
}

# Root domain A record
resource "cloudflare_record" "root" {
  zone_id = local.zone_id
  name    = var.domain
  content = var.homeserver_ip
  type    = "A"
  proxied = var.cloudflare_proxied
  ttl     = 1 # Auto when proxied
  comment = "Root domain - managed by Terraform"
}

# Git subdomain A record
resource "cloudflare_record" "git" {
  zone_id = local.zone_id
  name    = "git"
  content = var.homeserver_ip
  type    = "A"
  proxied = var.cloudflare_proxied
  ttl     = 1 # Auto when proxied
  comment = "Forgejo git server - managed by Terraform"
}

# Media subdomain A record
resource "cloudflare_record" "media" {
  zone_id = local.zone_id
  name    = "media"
  content = var.homeserver_ip
  type    = "A"
  proxied = var.cloudflare_proxied
  ttl     = 1 # Auto when proxied
  comment = "Jellyfin media server - managed by Terraform"
}
