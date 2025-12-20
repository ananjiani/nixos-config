variable "domain" {
  description = "Primary domain name"
  type        = string
  default     = "dimensiondoor.xyz"
}

variable "homeserver_ip" {
  description = "Public IP address of the homeserver"
  type        = string
  default     = "76.201.4.6"
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
