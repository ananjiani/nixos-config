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

# =============================================================================
# Kea DHCP Configuration
# =============================================================================
# Kea is the modern DHCP server (successor to ISC DHCP).
# Prerequisites: Enable Kea DHCPv4 in OPNsense UI before applying.

resource "opnsense_kea_subnet" "lan" {
  subnet      = var.lan_subnet
  description = "LAN DHCP subnet"

  pools       = ["192.168.1.100-192.168.1.254"]
  routers     = [var.opnsense_host]
  dns_servers = [var.opnsense_host]
}

resource "opnsense_kea_reservation" "access_point" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.2"
  mac_address = local.mac_addresses.access_point
  hostname    = "ap"
  description = "KuWFi AX835 Wireless Access Point"
}

resource "opnsense_kea_reservation" "switch" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.3"
  mac_address = local.mac_addresses.switch
  hostname    = "switch"
  description = "TP-Link TL-SG108E Managed Switch"
}

resource "opnsense_kea_reservation" "chromecast" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.10"
  mac_address = local.mac_addresses.chromecast
  hostname    = "chromecast"
  description = "Google Chromecast"
}

resource "opnsense_kea_reservation" "jellyfin" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.11"
  mac_address = local.mac_addresses.jellyfin
  hostname    = "jellyfin"
  description = "Jellyfin homeserver (future)"
}
