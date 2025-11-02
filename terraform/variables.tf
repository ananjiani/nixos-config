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
