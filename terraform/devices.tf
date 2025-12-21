# Device MAC Addresses
#
# MAC addresses for DHCP static reservations.
# These aren't encrypted since they're broadcast openly on the network anyway.

locals {
  mac_addresses = {
    access_point = "XX:XX:XX:XX:XX:XX" # KuWFi AX835 Wireless Access Point
    switch       = "XX:XX:XX:XX:XX:XX" # TP-Link TL-SG108E Managed Switch
    chromecast   = "XX:XX:XX:XX:XX:XX" # Google Chromecast (IoT VLAN)
    jellyfin     = "XX:XX:XX:XX:XX:XX" # Jellyfin homeserver (future)
  }
}
