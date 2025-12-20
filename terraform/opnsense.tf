# OPNsense Firewall Configuration
#
# This file manages firewall aliases and rules via Terraform.
# Changes here will be applied to your OPNsense router.

# =============================================================================
# Firewall Aliases
# =============================================================================
# Aliases are named groups of IPs, networks, or ports that can be referenced
# in firewall rules. They make rules more readable and easier to maintain.

# RFC1918 private network ranges - useful for blocking inbound from WAN
resource "opnsense_firewall_alias" "rfc1918" {
  name        = "rfc1918"
  type        = "network"
  description = "Private network ranges (RFC1918)"
  content     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# LAN network alias - references your local subnet
resource "opnsense_firewall_alias" "lan_network" {
  name        = "lan_network"
  type        = "network"
  description = "Local LAN subnet"
  content     = [var.lan_subnet]
}

# =============================================================================
# Firewall Rules
# =============================================================================
# Rules are processed in order. The 'sequence' field determines priority
# (lower numbers = higher priority, processed first).

# Anti-lockout rule: Always allow access to the router's web interface
# This prevents you from accidentally locking yourself out
resource "opnsense_firewall_filter" "anti_lockout" {
  enabled     = true
  sequence    = 1
  description = "Anti-lockout: Allow LAN access to router HTTPS"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"

    destination = {
      net  = "(self)"
      port = "443"
    }
  }
}

# Allow all outbound traffic from LAN
# This is the basic "allow LAN to internet" rule
resource "opnsense_firewall_filter" "lan_to_any" {
  enabled     = true
  sequence    = 10
  description = "Allow LAN to any destination"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
  }
}
