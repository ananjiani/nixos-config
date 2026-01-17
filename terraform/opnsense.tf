# OPNsense Firewall Configuration
#
# This file manages firewall aliases and rules via Terraform.
# Changes here will be applied to your OPNsense router.

# =============================================================================
# WireGuard VPN (Mullvad)
# =============================================================================
# WireGuard client configuration for Mullvad VPN.
# Note: WireGuard is built into OPNsense 24.1.2+ (no plugin needed).
#
# MANUAL STEPS REQUIRED after terraform apply:
# 1. Interfaces > Assignments: Add wg0 as WAN_MULLVAD
# 2. Enable the interface with IP from Mullvad (e.g., 10.x.x.x/32)
# 3. System > Gateways > Add: Create Mullvad_VPNV4 gateway pointing to WAN_MULLVAD

resource "opnsense_wireguard_client" "mullvad_peer" {
  name           = "mullvad-server"
  enabled        = true
  public_key     = data.sops_file.secrets.data["mullvad_server_pubkey"]
  tunnel_address = ["0.0.0.0/0"] # Route all traffic
  server_address = data.sops_file.secrets.data["mullvad_server"]
  server_port    = 51820
  keep_alive     = 25
}

resource "opnsense_wireguard_server" "mullvad" {
  name           = "mullvad"
  enabled        = true
  private_key    = data.sops_file.secrets.data["mullvad_private_key"]
  public_key     = data.sops_file.secrets.data["mullvad_public_key"]
  tunnel_address = [data.sops_file.secrets.data["mullvad_address"]]
  peers          = [opnsense_wireguard_client.mullvad_peer.id]
  port           = 51820
  mtu            = 1280 # Lower MTU for WireGuard overhead
  disable_routes = true # Required for policy-based routing
}

# =============================================================================
# Firewall Aliases
# =============================================================================
# Aliases are named groups of IPs, networks, or ports that can be referenced
# in firewall rules. They make rules more readable and easier to maintain.

# Google DNS servers - blocked to force devices to use local DNS (AdGuard)
# Chromecast and Android TV are hardcoded to use these, ignoring DHCP DNS
resource "opnsense_firewall_alias" "google_dns" {
  name        = "Google_DNS"
  type        = "host"
  description = "Google DNS servers (blocked to enforce local DNS)"
  content     = ["8.8.8.8", "8.8.4.4"]
}

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

# VPN exempt devices - these bypass the VPN and use WAN directly
resource "opnsense_firewall_alias" "vpn_exempt_devices" {
  name        = "VPN_Exempt"
  type        = "host"
  description = "Devices that bypass VPN and use WAN directly"
  content = [
    "192.168.1.10", # chromecast (needs direct WAN for Private DNS bootstrap)
    "192.168.1.25", # frodo (Home Assistant - cloud integrations require non-VPN)
    "192.168.1.50", # ammars-pc
    "192.168.1.51", # phone
  ]
}

# VPN exempt destinations - these endpoints bypass VPN for all devices
resource "opnsense_firewall_alias" "vpn_exempt_destinations" {
  name        = "VPN_Exempt_Dest"
  type        = "host"
  description = "Destinations that bypass VPN (WAF blocks Mullvad IPs)"
  content = [
    "api.deepseek.com",
    "api.tavily.com",
  ]
}

# =============================================================================
# Firewall Rules
# =============================================================================
# Rules are processed in order. The 'sequence' field determines priority
# (lower numbers = higher priority, processed first).

# Block Google DNS - forces Chromecast/Android TV to use DHCP-provided DNS (AdGuard)
# These devices are hardcoded to use 8.8.8.8/8.8.4.4, ignoring manual DNS settings
resource "opnsense_firewall_filter" "block_google_dns_udp" {
  enabled     = false # TEMPORARILY DISABLED - breaking cluster DNS
  sequence    = 2
  description = "Block Google DNS UDP (force local DNS)"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = opnsense_firewall_alias.google_dns.name
      port = "53"
    }
  }
}

resource "opnsense_firewall_filter" "block_google_dns_tcp" {
  enabled     = false # TEMPORARILY DISABLED - breaking cluster DNS
  sequence    = 3
  description = "Block Google DNS TCP (force local DNS)"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "TCP"

    destination = {
      net  = opnsense_firewall_alias.google_dns.name
      port = "53"
    }
  }
}

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

# VPN-exempt destinations bypass VPN (for services that block Mullvad IPs)
resource "opnsense_firewall_filter" "vpn_exempt_destinations" {
  count       = var.vpn_gateway_configured ? 1 : 0
  enabled     = true
  sequence    = 4
  description = "VPN exempt: Route to specific destinations via WAN"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"

    destination = {
      net  = opnsense_firewall_alias.vpn_exempt_destinations.name
      port = "443"
    }
  }

  source_routing = {
    gateway = var.wan_gateway_name
  }
}

# VPN-exempt devices bypass VPN and use WAN directly
resource "opnsense_firewall_filter" "vpn_exempt_lan" {
  count       = var.vpn_gateway_configured ? 1 : 0
  enabled     = true
  sequence    = 5
  description = "VPN exempt: LAN devices bypass VPN"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"

    source = {
      net = opnsense_firewall_alias.vpn_exempt_devices.name
    }
  }

  source_routing = {
    gateway = var.wan_gateway_name
  }
}

# Block IPv6 DNS to force Chromecast to use IPv4 DNS (which gets NAT redirected to AdGuard)
resource "opnsense_firewall_filter" "block_ipv6_dns_udp" {
  enabled     = true
  sequence    = 7
  description = "Block IPv6 DNS UDP (force IPv4 DNS for Chromecast)"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action      = "block"
    direction   = "in"
    ip_protocol = "inet6"
    protocol    = "UDP"

    destination = {
      port = "53"
    }
  }
}

resource "opnsense_firewall_filter" "block_ipv6_dns_tcp" {
  enabled     = true
  sequence    = 8
  description = "Block IPv6 DNS TCP (force IPv4 DNS for Chromecast)"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action      = "block"
    direction   = "in"
    ip_protocol = "inet6"
    protocol    = "TCP"

    destination = {
      port = "53"
    }
  }
}

# Allow LAN-to-LAN traffic without VPN (local services must be reachable)
resource "opnsense_firewall_filter" "lan_to_lan" {
  count       = var.vpn_gateway_configured ? 1 : 0
  enabled     = true
  sequence    = 6
  description = "Allow LAN to local destinations (no VPN)"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.rfc1918.name
    }
  }

  # No gateway = direct routing, bypasses VPN
}

# Allow all outbound traffic from LAN
# When VPN gateway is configured, routes through Mullvad VPN
resource "opnsense_firewall_filter" "lan_to_any" {
  enabled     = true
  sequence    = 10
  description = var.vpn_gateway_configured ? "Allow LAN to any destination (via VPN)" : "Allow LAN to any destination"

  interface = {
    interface = ["lan"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
  }

  source_routing = {
    gateway = var.vpn_gateway_configured ? var.vpn_gateway_name : ""
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
  dns_servers = ["192.168.1.53"] # AdGuard Home (k8s MetalLB VIP)
}

resource "opnsense_kea_reservation" "kuwfi_ap" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.2"
  mac_address = local.mac_addresses.kuwfi_ap
  hostname    = "kuwfi-ap"
  description = "KuWFi AX835 Wireless Access Point"
}

resource "opnsense_kea_reservation" "tl_sg108e" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.3"
  mac_address = local.mac_addresses.tl_sg108e
  hostname    = "tl-sg108e"
  description = "TP-Link TL-SG108E Managed Switch"
}

resource "opnsense_kea_reservation" "tl_sg108pe" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.4"
  mac_address = local.mac_addresses.tl_sg108pe
  hostname    = "tl-sg108pe"
  description = "TP-Link TL-SG108PE PoE Switch"
}

resource "opnsense_kea_reservation" "chromecast" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.10"
  mac_address = local.mac_addresses.chromecast
  hostname    = "chromecast"
  description = "Google Chromecast"
}

resource "opnsense_kea_reservation" "gondor" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.20"
  mac_address = local.mac_addresses.gondor
  hostname    = "gondor"
  description = "Proxmox VE Server"
}

resource "opnsense_kea_reservation" "boromir" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.21"
  mac_address = local.mac_addresses.boromir
  hostname    = "boromir"
  description = "NixOS VM (main server)"
}

resource "opnsense_kea_reservation" "ammars_pc" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.50"
  mac_address = local.mac_addresses.ammars_pc
  hostname    = "ammars-pc"
  description = "Desktop PC (VPN exempt)"
}

resource "opnsense_kea_reservation" "phone" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.51"
  mac_address = local.mac_addresses.phone
  hostname    = "ammars-phone"
  description = "Phone (VPN exempt)"
}

resource "opnsense_kea_reservation" "the_shire" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.23"
  mac_address = local.mac_addresses.the_shire
  hostname    = "the-shire"
  description = "The Shire"
}

resource "opnsense_kea_reservation" "rohan" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.24"
  mac_address = local.mac_addresses.rohan
  hostname    = "rohan"
  description = "Rohan"
}

resource "opnsense_kea_reservation" "frodo" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.25"
  mac_address = local.mac_addresses.frodo
  hostname    = "frodo"
  description = "Home Assistant OS VM"
}

resource "opnsense_kea_reservation" "samwise" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.26"
  mac_address = local.mac_addresses.samwise
  hostname    = "samwise"
  description = "Zigbee2MQTT and MQTT Broker VM"
}

resource "opnsense_kea_reservation" "theoden" {
  subnet_id   = opnsense_kea_subnet.lan.id
  ip_address  = "192.168.1.27"
  mac_address = local.mac_addresses.theoden
  hostname    = "theoden"
  description = "k3s server VM"
}

# =============================================================================
# Port Forwarding for Traefik (k8s ingress)
# =============================================================================
# Port forwarding not supported by browningluke/opnsense provider.
#
# MANUAL STEPS REQUIRED in OPNsense UI (Firewall → NAT → Port Forward):
#
# Rule 1 - HTTPS (443):
#   Interface: WAN
#   Protocol: TCP
#   Destination: WAN address, port 443
#   Redirect target IP: 192.168.1.52 (Traefik LoadBalancer)
#   Redirect target port: 443
#   Description: HTTPS to Traefik (k8s ingress)
#
# Rule 2 - HTTP (80) for ACME challenges:
#   Interface: WAN
#   Protocol: TCP
#   Destination: WAN address, port 80
#   Redirect target IP: 192.168.1.52 (Traefik LoadBalancer)
#   Redirect target port: 80
#   Description: HTTP to Traefik (ACME challenges)

# =============================================================================
# DNS Configuration
# =============================================================================
# DNS is handled by AdGuard Home on boromir (192.168.1.21).
# DHCP hands out boromir as the DNS server (see dns_servers in kea_subnet).
#
# MANUAL STEPS REQUIRED:
# 1. Disable Unbound: Services → Unbound DNS → Uncheck "Enable"
# 2. Set OPNsense DNS: System → Settings → General → DNS servers: 192.168.1.21
#    Uncheck "Allow DNS server list to be overridden by DHCP/PPP on WAN"

# resource "opnsense_kea_reservation" "jellyfin" {
#   subnet_id   = opnsense_kea_subnet.lan.id
#   ip_address  = "192.168.1.11"
#   mac_address = local.mac_addresses.jellyfin
#   hostname    = "jellyfin"
#   description = "Jellyfin homeserver (future)"
# }

# =============================================================================
# VPN Interface Firewall Rules
# =============================================================================
# Allow return traffic on the VPN interface

resource "opnsense_firewall_filter" "vpn_allow_inbound" {
  count       = var.vpn_gateway_configured ? 1 : 0
  enabled     = true
  sequence    = 1
  description = "Allow VPN inbound traffic"

  interface = {
    interface = ["opt3"]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
  }
}

# =============================================================================
# Outbound NAT for VPN
# =============================================================================
# NAT rules must be created MANUALLY in OPNsense UI due to a known bug where
# rules created via API fail to load with "no IP address found for opt3".
# See: https://github.com/opnsense/core/issues/2171
#
# Manual NAT rule settings (Firewall → NAT → Outbound → Add):
#   Interface: VPN
#   Source: 192.168.1.0/24 (LAN) or 10.10.10.0/24 (Guest)
#   Translation/target: 10.72.129.112 (Mullvad tunnel IP)
#
# resource "opnsense_firewall_nat" "lan_to_vpn" {
#   count       = var.vpn_gateway_configured ? 1 : 0
#   enabled     = true
#   sequence    = 100
#   description = "NAT LAN to WireGuard VPN"
#   interface   = "opt3"
#   protocol    = "any"
#   ip_protocol = "inet"
#
#   source = {
#     net = var.lan_subnet
#   }
#
#   target = {
#     ip = split("/", data.sops_file.secrets.data["mullvad_address"])[0]
#   }
# }
#
# resource "opnsense_firewall_nat" "guest_to_vpn" {
#   count       = var.vpn_gateway_configured ? 1 : 0
#   enabled     = true
#   sequence    = 101
#   description = "NAT Guest to WireGuard VPN"
#   interface   = "opt3"
#   protocol    = "any"
#   ip_protocol = "inet"
#
#   source = {
#     net = var.guest_subnet
#   }
#
#   target = {
#     ip = split("/", data.sops_file.secrets.data["mullvad_address"])[0]
#   }
# }
