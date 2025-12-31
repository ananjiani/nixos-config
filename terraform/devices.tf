# Device MAC Addresses
#
# MAC addresses for DHCP static reservations.
# These aren't encrypted since they're broadcast openly on the network anyway.

locals {
  mac_addresses = {
    kuwfi_ap   = "9c:e5:49:60:3c:1b" # KuWFi AX835 Wireless Access Point
    tl_sg108e   = "60:83:e7:71:f2:18" # TP-Link TL-SG108E Managed Switch
    tl_sg108pe  = "dc:62:79:3b:00:d6" # TP-Link TL-SG108PE PoE Switch
    chromecast = "1c:53:f9:04:40:9d" # Google Chromecast
    gondor     = "b4:2e:99:39:df:9e" # Proxmox VE Server
    boromir    = "bc:24:11:f9:37:2e" # NixOS VM (main server)
    ammars_pc  = "30:c5:99:26:f4:c5" # Desktop PC (VPN exempt)
    phone      = "04:00:6e:82:70:17" # Phone (VPN exempt)
    the_shire  = "18:60:24:27:80:40" # The Shire
    rohan      = "bc:5f:f4:e9:25:8f" # Rohan
    # VMs on the-shire
    frodo   = "02:33:3E:B2:81:19" # HAOS VM
    samwise = "BC:24:11:00:01:03" # NixOS VM (update after creation)
    # VMs on rohan
    theoden = "BC:24:11:00:01:04" # k3s server VM
  }
}
