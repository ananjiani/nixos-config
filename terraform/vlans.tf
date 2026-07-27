# Guest and IoT VLAN Configuration
#
# This file manages VLAN interfaces, firewall rules, and DHCP for isolated networks.
#
# MANUAL STEPS REQUIRED (OPNsense API doesn't support these):
# 1. Interfaces > Assignments: Add VLAN interfaces and assign IPs
#    - Guest: 10.10.10.1/24
#    - IoT: 10.20.20.1/24
#    - Work: 10.30.30.1/24 (then set work_vlan_interface_configured = true)
#      Work/opt4 IPv6 Configuration Type = None
# 2. Services > Kea DHCPv4 > Settings: Add Guest/IoT/Work to "Active Interfaces"
# 3. Services > mDNS Repeater (for Chromecast discovery from Guest network):
#    - Enable: checked
#    - Interfaces: select LAN and Guest
# 4. Firewall > NAT > Outbound: verify automatic/hybrid WAN outbound NAT covers 10.30.30.0/24
# 5. Firewall > Rules / DNS redirect: verify manual DNS redirect rules do NOT include Work/opt4
# 6. Before first Denethor boot:
#    - Gondor vmbr0: VLAN-aware + VID 30 tagged
#    - Switch trunk: VID 30 tagged toward Gondor

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

resource "opnsense_interfaces_vlan" "work" {
  parent      = var.vlan_parent_interface
  tag         = var.work_vlan_tag
  priority    = 0
  description = "Work Network"
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

resource "opnsense_firewall_alias" "work_network" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  name        = "work_network"
  type        = "network"
  description = "Work VLAN subnet"
  content     = [var.work_subnet]
}

resource "opnsense_firewall_alias" "denethor_host" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  name        = "denethor"
  type        = "host"
  description = "Denethor work VM"
  content     = ["10.30.30.10"]
}

# Only these two LAN hosts may reach the work VM (SSH admin access).
resource "opnsense_firewall_alias" "work_admin_hosts" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  name        = "work_admin_hosts"
  type        = "host"
  description = "LAN hosts allowed to SSH into the work VM"
  content = [
    "192.168.1.50", # ammars-pc
    "192.168.1.28", # aragorn
  ]
}

# Superset of rfc1918 plus Tailscale's CGNAT range — the work VM must not
# reach the homelab LAN, the other VLANs, or anything on the tailnet.
resource "opnsense_firewall_alias" "work_blocked_networks" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  name        = "work_blocked_networks"
  type        = "network"
  description = "Private + Tailscale CGNAT ranges blocked from the Work VLAN"
  content = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "100.64.0.0/10",
  ]
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

# Block Guest -> Work (only when both Guest and Work aliases exist)
resource "opnsense_firewall_filter" "guest_block_work" {
  count       = var.vlan_interfaces_configured && var.work_vlan_interface_configured ? 1 : 0
  enabled     = true
  sequence    = 112
  description = "Block Guest to Work"

  interface = {
    interface = [var.guest_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.work_network[0].name
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

# Block IoT -> Work (only when both IoT and Work aliases exist)
resource "opnsense_firewall_filter" "iot_block_work" {
  count       = var.vlan_interfaces_configured && var.work_vlan_interface_configured ? 1 : 0
  enabled     = true
  sequence    = 212
  description = "Block IoT to Work"

  interface = {
    interface = [var.iot_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.work_network[0].name
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
# Work VLAN Firewall Rules (Sequence 300-399)
# =============================================================================
# Router DHCP only (no DNS to the router — OPNsense Unbound is stopped, so
# 10.30.30.1:53 is dead). Hosts use public Quad9; DNS egress rides the
# direct-WAN internet rule below. Everything private is blocked, then internet
# via the WAN gateway — never the Mullvad gateway, so corporate VPN and SAML
# MFA see a normal residential IP.

# Allow Work to access router for DHCP
resource "opnsense_firewall_filter" "work_to_router_dhcp" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  enabled     = true
  sequence    = 300
  description = "Allow Work DHCP"

  interface = {
    interface = [var.work_interface]
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

# Block Work -> LAN / Guest / IoT / Tailscale (everything private)
resource "opnsense_firewall_filter" "work_block_private" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  enabled     = true
  sequence    = 310
  description = "Block Work to private networks"

  interface = {
    interface = [var.work_interface]
  }

  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"

    destination = {
      net = opnsense_firewall_alias.work_blocked_networks[0].name
    }
  }
}

# Block all IPv6 on Work (host also disables IPv6; this hardens the boundary)
resource "opnsense_firewall_filter" "work_block_ipv6" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  enabled     = true
  sequence    = 311
  description = "Block Work IPv6"

  interface = {
    interface = [var.work_interface]
  }

  filter = {
    action      = "block"
    direction   = "in"
    ip_protocol = "inet6"
    protocol    = "any"
  }
}

# Allow Work -> Internet, pinned to the WAN gateway (never Mullvad)
resource "opnsense_firewall_filter" "work_to_internet" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  enabled     = true
  sequence    = 390
  description = "Allow Work to Internet (direct WAN)"

  interface = {
    interface = [var.work_interface]
  }

  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
  }

  source_routing = {
    gateway = var.wan_gateway_name
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

resource "opnsense_kea_subnet" "work" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  subnet      = var.work_subnet
  description = "Work VLAN DHCP"
  pools       = [var.work_dhcp_pool]
  routers     = [var.work_gateway]
  # Public Quad9 only — router DNS is dead (Unbound stopped). Matches
  # hosts/servers/denethor nameservers. Egress via work_to_internet WAN rule.
  dns_servers = ["9.9.9.9", "149.112.112.112"]
}

resource "opnsense_kea_reservation" "denethor" {
  count       = var.work_vlan_interface_configured ? 1 : 0
  subnet_id   = opnsense_kea_subnet.work[0].id
  ip_address  = "10.30.30.10"
  mac_address = local.mac_addresses.denethor
  hostname    = "denethor"
  description = "Work VM (Proxmox VM on gondor)"
}
