# Canonical Syncthing device IDs, keyed by hostname.
#
# Companion to lib/hosts.nix. That file holds LAN addresses and is mirrored in
# terraform; these IDs cannot be, because they derive from each machine's TLS
# certificate in its Syncthing data directory and are therefore per-install. A
# reinstalled host gets a new ID and this file must be updated to match.
#
# Consumed by:
#   - modules/dendritic/gaming.nix (Home Manager instances)
#   - hosts/servers/theoden/configuration.nix (NixOS service)
#
# Because the IDs are per-install, services.syncthing.overrideDevices is set to
# false at both call sites: declared peers are still enforced, but a device
# added by hand after a reinstall is not deleted on the next activation.
#
# Verify a host's ID with:
#   grep -oE '<device id="[A-Z0-9-]+" name="[^"]*"' \
#     ~/.local/state/syncthing/config.xml
#
# Collected 2026-10-03.
{
  ammars-pc = {
    id = "6IGLDZ7-EFEOYFI-YZ3AOX7-XAANEKQ-RIUYV46-BXMQ5U6-6KRKNT6-IYZTMAR";
  };
  steamdeck = {
    id = "GEATA6B-FZE24BO-ZRYT7HR-Q6YJWTO-UVKTDH6-V7Y6UJW-72SCUOK-GOH2KAG";
  };
  steammachine = {
    id = "3J3YZD7-RHHVFRB-CG5XQJ5-RXC537W-DJIX7CZ-B3T27PM-T2UGQJ5-JRXBAAG";
  };
  theoden = {
    id = "MPYF5B4-TPM5UBE-J74OBPC-XEWUQGE-D56G66W-YSBTFRU-7YHPXOV-YRNFGQG";
  };
}
