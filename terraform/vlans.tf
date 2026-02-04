# Guest and IoT VLAN Configuration
#
# This file manages VLAN interfaces, firewall rules, and DHCP for isolated networks.
#
# MANUAL STEPS REQUIRED (OPNsense API doesn't support these):
# 1. Interfaces > Assignments: Add VLAN interfaces and assign IPs
#    - Guest: 10.10.10.1/24
#    - IoT: 10.20.20.1/24
# 2. Services > Kea DHCPv4 > Settings: Add Guest/IoT to "Active Interfaces"
# 3. Services > mDNS Repeater (for Chromecast discovery from Guest network):
#    - Enable: checked
#    - Interfaces: select LAN and Guest

# =============================================================================
# VLAN Interfaces
# =============================================================================
# These create the 802.1Q VLAN tags on the parent interface.
# After applying, you must manually assign IPs in OPNsense UI.

resource "opnsense_interfaces_vlan" "guest" {
  parent      = var.vlan_parent_interface
  tag         = var.guest_vlan_tag
  priority    = 0
  description = "Guest Network"
}

resource "opnsense_interfaces_vlan" "iot" {
  parent      = var.vlan_parent_interface
  tag         = var.iot_vlan_tag
  priority    = 0
  description = "IoT Network"
}

# =============================================================================
# Firewall Aliases
# =============================================================================
# Only created after interfaces are manually configured in OPNsense UI.

resource "opnsense_firewall_alias" "guest_network" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  name        = "guest_network"
  type        = "network"
  description = "Guest VLAN subnet"
  content     = [var.guest_subnet]
}

resource "opnsense_firewall_alias" "iot_network" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  name        = "iot_network"
  type        = "network"
  description = "IoT VLAN subnet"
  content     = [var.iot_subnet]
}

resource "opnsense_firewall_alias" "chromecast_ips" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  name        = "chromecast_ips"
  type        = "host"
  description = "Chromecast IPs (WiFi + Ethernet)"
  content     = ["192.168.1.10", "192.168.1.11"]
}

resource "opnsense_firewall_alias" "chromecast_tcp_ports" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  name        = "chromecast_tcp_ports"
  type        = "port"
  description = "Chromecast TCP ports (control, mirroring)"
  content     = ["8008", "8009", "8443"]
}

resource "opnsense_firewall_alias" "chromecast_udp_ports" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  name        = "chromecast_udp_ports"
  type        = "port"
  description = "Chromecast UDP ports (RTP/RTCP streaming)"
  content     = ["32768:61000"]
}

# =============================================================================
# Guest VLAN Firewall Rules (Sequence 100-199)
# =============================================================================
# Rule order: Allow router access, allow Chromecast, block private networks, then allow internet

# Allow Guest to access router for DHCP
resource "opnsense_firewall_filter" "guest_to_router_dhcp" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 100
  description = "Allow Guest DHCP"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = "(self)"
      port = "67-68"
    }
  }
}

# Allow Guest to access router for DNS
resource "opnsense_firewall_filter" "guest_to_router_dns" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 101
  description = "Allow Guest DNS"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = "(self)"
      port = "53"
    }
  }
}

# Allow Guest mDNS for Chromecast discovery
resource "opnsense_firewall_filter" "guest_mdns" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 102
  description = "Allow Guest mDNS"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = "224.0.0.251"
      port = "5353"
    }
  }
}

# Allow Guest -> Chromecast TCP (control, mirroring)
resource "opnsense_firewall_filter" "guest_to_chromecast_tcp" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 105
  description = "Allow Guest to Chromecast TCP"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"

    destination = {
      net  = opnsense_firewall_alias.chromecast_ips[0].name
      port = opnsense_firewall_alias.chromecast_tcp_ports[0].name
    }
  }
}

# Allow Guest -> Chromecast UDP (RTP/RTCP streaming)
resource "opnsense_firewall_filter" "guest_to_chromecast_udp" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 106
  description = "Allow Guest to Chromecast UDP"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = opnsense_firewall_alias.chromecast_ips[0].name
      port = opnsense_firewall_alias.chromecast_udp_ports[0].name
    }
  }
}

# Block Guest -> LAN
resource "opnsense_firewall_filter" "guest_block_lan" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 110
  description = "Block Guest to LAN"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.lan_network.name
    }
  }
}

# Block Guest -> IoT
resource "opnsense_firewall_filter" "guest_block_iot" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 111
  description = "Block Guest to IoT"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.iot_network[0].name
    }
  }
}

# Allow Guest -> Internet
# When VPN gateway is configured, routes through Mullvad VPN
resource "opnsense_firewall_filter" "guest_to_internet" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 190
  description = var.vpn_gateway_configured ? "Allow Guest to Internet (via VPN)" : "Allow Guest to Internet"

  interface = {
    interface = [var.guest_interface]
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
# IoT VLAN Firewall Rules (Sequence 200-299)
# =============================================================================

# Allow IoT to access router for DHCP
resource "opnsense_firewall_filter" "iot_to_router_dhcp" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 200
  description = "Allow IoT DHCP"

  interface = {
    interface = [var.iot_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = "(self)"
      port = "67-68"
    }
  }
}

# Allow IoT to access router for DNS
resource "opnsense_firewall_filter" "iot_to_router_dns" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 201
  description = "Allow IoT DNS"

  interface = {
    interface = [var.iot_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = "(self)"
      port = "53"
    }
  }
}

# Allow IoT mDNS for device discovery (Home Assistant, thermostats, etc.)
resource "opnsense_firewall_filter" "iot_mdns" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 202
  description = "Allow IoT mDNS"

  interface = {
    interface = [var.iot_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"

    destination = {
      net  = "224.0.0.251"
      port = "5353"
    }
  }
}

# Block IoT -> LAN
resource "opnsense_firewall_filter" "iot_block_lan" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 210
  description = "Block IoT to LAN"

  interface = {
    interface = [var.iot_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.lan_network.name
    }
  }
}

# Block IoT -> Guest
resource "opnsense_firewall_filter" "iot_block_guest" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 211
  description = "Block IoT to Guest"

  interface = {
    interface = [var.iot_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.guest_network[0].name
    }
  }
}

# Allow IoT -> Internet
resource "opnsense_firewall_filter" "iot_to_internet" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  enabled     = true
  sequence    = 290
  description = "Allow IoT to Internet"

  interface = {
    interface = [var.iot_interface]
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

resource "opnsense_kea_subnet" "guest" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  subnet      = var.guest_subnet
  description = "Guest VLAN DHCP"
  pools       = [var.guest_dhcp_pool]
  routers     = [var.guest_gateway]
  dns_servers = [var.guest_gateway]
}

resource "opnsense_kea_subnet" "iot" {
  count       = var.vlan_interfaces_configured ? 1 : 0
  subnet      = var.iot_subnet
  description = "IoT VLAN DHCP"
  pools       = [var.iot_dhcp_pool]
  routers     = [var.iot_gateway]
  dns_servers = [var.iot_gateway]
}
