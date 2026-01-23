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

# Bifrost LLM Gateway
resource "cloudflare_record" "bifrost" {
  zone_id = local.zone_id
  name    = "bifrost"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Bifrost LLM Gateway (internal) - managed by Terraform"
}

# Stremio streaming server (for web.stremio.com)
resource "cloudflare_record" "stremio" {
  zone_id = local.zone_id
  name    = "stremio"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Stremio streaming server (internal) - managed by Terraform"
}

# Comet addon for Stremio
resource "cloudflare_record" "comet" {
  zone_id = local.zone_id
  name    = "comet"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Comet Stremio addon (internal) - managed by Terraform"
}

# Prowlarr indexer manager
resource "cloudflare_record" "prowlarr" {
  zone_id = local.zone_id
  name    = "prowlarr"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Prowlarr indexer manager (internal) - managed by Terraform"
}

# AdGuard DNS-over-TLS (for Android Private DNS)
resource "cloudflare_record" "dns_dot" {
  zone_id = local.zone_id
  name    = "dns"
  content = "192.168.1.56" # AdGuard DoT LoadBalancer (internal)
  type    = "A"
  proxied = false # Must be false for DoT
  ttl     = 300
  comment = "AdGuard DNS-over-TLS (internal) - managed by Terraform"
}

# Scriberr AI transcription
resource "cloudflare_record" "scriberr" {
  zone_id = local.zone_id
  name    = "scriberr"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "Scriberr AI transcription (internal) - managed by Terraform"
}

# LobeChat AI workspace
resource "cloudflare_record" "lobe" {
  zone_id = local.zone_id
  name    = "lobe"
  content = "192.168.1.52" # Traefik LoadBalancer (internal)
  type    = "A"
  proxied = false # Internal IP, cannot be proxied
  ttl     = 300
  comment = "LobeChat AI workspace (internal) - managed by Terraform"
}

# =============================================================================
# Cloudflare Tunnel Services
# =============================================================================

# Buildbot CI/CD (via Cloudflare Tunnel for Codeberg webhooks)
resource "cloudflare_record" "buildbot" {
  zone_id = local.zone_id
  name    = "ci"
  content = "b33ec739-7324-4c6f-b6fa-daedbe0828c8.cfargotunnel.com"
  type    = "CNAME"
  proxied = true # Must be proxied for Cloudflare Tunnel
  ttl     = 1    # Auto when proxied
  comment = "Buildbot CI/CD (Cloudflare Tunnel) - managed by Terraform"
}
