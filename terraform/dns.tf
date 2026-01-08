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

# Forgejo git server (internal via Tailscale)
resource "cloudflare_record" "git" {
  zone_id = local.zone_id
  name    = "git"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Forgejo git server (internal) - managed by Terraform"
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

# Spatial Jobs Index API subdomain A record (VPS)
resource "cloudflare_record" "sji_api" {
  zone_id = local.zone_id
  name    = "sji-api"
  content = "159.223.139.52"
  type    = "A"
  proxied = false
  ttl     = 300
  comment = "Spatial Jobs Index API (VPS) - managed by Terraform"
}

# Tailscale/Headscale control server
resource "cloudflare_record" "tailscale" {
  zone_id = local.zone_id
  name    = "ts"
  content = var.homeserver_ip
  type    = "A"
  proxied = false # Must be false for Tailscale coordination
  ttl     = 300
  comment = "Headscale control server (boromir) - managed by Terraform"
}

# =============================================================================
# Internal Services (point to Traefik LoadBalancer IP)
# =============================================================================

# Authentik SSO
resource "cloudflare_record" "auth" {
  zone_id = local.zone_id
  name    = "auth"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Authentik SSO (internal) - managed by Terraform"
}

# Immich photo management
resource "cloudflare_record" "immich" {
  zone_id = local.zone_id
  name    = "immich"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Immich photo management (internal) - managed by Terraform"
}

# Open WebUI AI chat
resource "cloudflare_record" "ai" {
  zone_id = local.zone_id
  name    = "ai"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Open WebUI AI chat (internal) - managed by Terraform"
}

# Homepage dashboard
resource "cloudflare_record" "home" {
  zone_id = local.zone_id
  name    = "home"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Homepage dashboard (internal) - managed by Terraform"
}
