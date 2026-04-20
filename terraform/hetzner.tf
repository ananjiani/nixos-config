# Hetzner Cloud Configuration
#
# Manages the erebor VPS (OpenBao secrets manager).
#
# Prerequisites:
# 1. Create API token in Hetzner Cloud Console (Project → Security → API Tokens)
# 2. Add token to secrets/secrets.yaml as hcloud_token
# 3. Ensure ~/.ssh/id_ed25519.pub exists

# =============================================================================
# SSH Key
# =============================================================================

resource "hcloud_ssh_key" "default" {
  name       = "ammar"
  public_key = file(var.ssh_public_key_path)
}

# =============================================================================
# Erebor - OpenBao Secrets Manager VPS
# =============================================================================

resource "hcloud_server" "erebor" {
  name        = "erebor"
  image       = "ubuntu-24.04" # Throwaway — replaced by nixos-anywhere before use
  server_type = var.hetzner_server_type
  location    = var.hetzner_location
  ssh_keys    = [hcloud_ssh_key.default.id]

  labels = {
    role       = "secrets"
    service    = "openbao"
    managed_by = "terraform"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # NixOS installation: after `terraform apply`, run nixos-anywhere to install
  # the full NixOS config (with disko partitioning) in one shot:
  #
  #   nix run github:nix-community/nixos-anywhere -- --flake .#erebor root@<ipv4>
  #
  # This kexec's into NixOS, partitions via disko, and deploys the erebor config.

  lifecycle {
    ignore_changes = [
      image,
      ssh_keys,
    ]
  }
}

# =============================================================================
# Firewall
# =============================================================================
# OpenBao is accessed exclusively over Tailscale (port 8200/8201 not public).
# Port 443 is exposed publicly for Caddy + Headscale (control plane for the
# tailnet itself — cannot live behind Tailscale).

resource "hcloud_firewall" "erebor" {
  name = "erebor-firewall"

  # SSH access
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # Tailscale WireGuard (UDP 41641)
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "41641"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # Caddy HTTPS (Headscale control plane TLS termination).
  # DNS-01 ACME is used for certs, so port 80 is NOT opened.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall_attachment" "erebor" {
  firewall_id = hcloud_firewall.erebor.id
  server_ids  = [hcloud_server.erebor.id]
}
