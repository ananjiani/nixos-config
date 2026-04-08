# Canonical LAN host → IP mapping
#
# Single source of truth for:
#   - modules/nixos/networking.nix (/etc/hosts)
#   - modules/nixos/server/keepalived.nix (VRRP unicast peers)
#   - modules/nixos/server/k3s.nix (--node-ip / --node-external-ip)
#   - modules/nixos/server/adguard.nix (DNS rewrites)
#
# Terraform Kea DHCP reservations (opnsense.tf) are managed separately.
# Erebor excluded — Hetzner VPS, not on LAN (Tailscale IP in vault-agent.nix).
{
  router = "192.168.1.1";
  gondor = "192.168.1.20";
  boromir = "192.168.1.21";
  the-shire = "192.168.1.23";
  rohan = "192.168.1.24";
  frodo = "192.168.1.25";
  samwise = "192.168.1.26";
  theoden = "192.168.1.27";
  rivendell = "192.168.1.29";
  ammars-pc = "192.168.1.50";
}
