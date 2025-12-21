# Device MAC Addresses
#
# MAC addresses for DHCP static reservations.
# These aren't encrypted since they're broadcast openly on the network anyway.

locals {
  mac_addresses = {
    kuwfi_ap  = "9c:e5:49:60:3c:1b" # KuWFi AX835 Wireless Access Point
    tl_sg108e = "60:83:e7:71:f2:18" # TP-Link TL-SG108E Managed Switch
    chromecast   = "1c:53:f9:04:40:9d" # Google Chromecast
    # jellyfin     = "XX:XX:XX:XX:XX:XX" # Jellyfin homeserver (future)
  }
}
