variable "domain" {
  description = "Primary domain name"
  type        = string
  default     = "dimensiondoor.xyz"
}

variable "homeserver_ip" {
  description = "Public IP address of the homeserver"
  type        = string
  default     = "72.182.230.42"
}

variable "cloudflare_proxied" {
  description = "Whether to proxy traffic through Cloudflare (orange cloud)"
  type        = bool
  default     = true
}

# OPNsense variables
variable "opnsense_host" {
  description = "OPNsense router IP address or hostname"
  type        = string
  default     = "192.168.1.1"
}

variable "lan_subnet" {
  description = "LAN network CIDR (e.g., 192.168.1.0/24)"
  type        = string
  default     = "192.168.1.0/24"
}

# =============================================================================
# VLAN Configuration
# =============================================================================

variable "vlan_parent_interface" {
  description = "Parent interface for VLANs (e.g., igb1)"
  type        = string
  default     = "igb1"
}

# Guest VLAN (VLAN 10)
variable "guest_vlan_tag" {
  description = "VLAN tag for Guest network"
  type        = number
  default     = 10
}

variable "guest_subnet" {
  description = "Guest network CIDR"
  type        = string
  default     = "10.10.10.0/24"
}

variable "guest_gateway" {
  description = "Guest network gateway IP"
  type        = string
  default     = "10.10.10.1"
}

variable "guest_dhcp_pool" {
  description = "Guest DHCP pool range"
  type        = string
  default     = "10.10.10.100-10.10.10.254"
}

variable "guest_interface" {
  description = "OPNsense interface name for Guest VLAN (set after manual assignment)"
  type        = string
  default     = "opt2"
}

# IoT VLAN (VLAN 20)
variable "iot_vlan_tag" {
  description = "VLAN tag for IoT network"
  type        = number
  default     = 20
}

variable "iot_subnet" {
  description = "IoT network CIDR"
  type        = string
  default     = "10.20.20.0/24"
}

variable "iot_gateway" {
  description = "IoT network gateway IP"
  type        = string
  default     = "10.20.20.1"
}

variable "iot_dhcp_pool" {
  description = "IoT DHCP pool range"
  type        = string
  default     = "10.20.20.100-10.20.20.254"
}

variable "iot_interface" {
  description = "OPNsense interface name for IoT VLAN (set after manual assignment)"
  type        = string
  default     = "opt1"
}

# Deployment control - set to true after manually configuring VLAN interfaces in OPNsense UI
variable "vlan_interfaces_configured" {
  description = "Set to true after manually assigning VLAN interfaces in OPNsense UI"
  type        = bool
  default     = true
}

# =============================================================================
# WireGuard VPN (Mullvad)
# =============================================================================
# Mullvad credentials are loaded from SOPS secrets:
#   - mullvad_private_key
#   - mullvad_public_key
#   - mullvad_address
#   - mullvad_server
#   - mullvad_server_pubkey

variable "vpn_gateway_configured" {
  description = "Set to true after manually creating VPN gateway in OPNsense UI"
  type        = bool
  default     = true
}

variable "vpn_gateway_name" {
  description = "Name of the VPN gateway in OPNsense (created manually after interface assignment)"
  type        = string
  default     = "Mullvad_VPNV4"
}

variable "wan_gateway_name" {
  description = "Name of the WAN gateway in OPNsense"
  type        = string
  default     = "WAN_DHCP"
}

# =============================================================================
# Proxmox Configuration
# =============================================================================

variable "proxmox_host" {
  description = "Proxmox VE host IP address or hostname"
  type        = string
  default     = "192.168.1.20"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "gondor"
}

variable "proxmox_datastore" {
  description = "Default datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_nodes" {
  description = "Proxmox cluster nodes (middle-earth)"
  type = map(object({
    host = string
  }))
  default = {
    gondor    = { host = "192.168.1.20" }
    the-shire = { host = "192.168.1.23" }
    rohan     = { host = "192.168.1.24" }
  }
}

# Disk IDs for faramir passthrough (get from: ls -la /dev/disk/by-id/ on Proxmox host)
variable "faramir_disk1_id" {
  description = "Disk ID for faramir data disk 1 (UUID: dc5e54fd-6474-4b88-a757-c31f62c37138)"
  type        = string
  default     = "ata-ST2000DM008-2FR102_ZFL4ERX1"
}

variable "faramir_disk2_id" {
  description = "Disk ID for faramir data disk 2 (UUID: 18cee265-e408-43bc-b6fe-c5edde8cb354)"
  type        = string
  default     = "ata-ST8000DM004-2U9188_ZR15RMQZ"
}

variable "faramir_parity_id" {
  description = "Disk ID for faramir parity disk (UUID: 15bc428e-291e-4380-a234-a2df4b4b0297)"
  type        = string
  default     = "ata-WDC_WD1002FAEX-00Z3A0_WD-WCATRA312386"
}
