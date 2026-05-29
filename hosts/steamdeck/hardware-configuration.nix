# TODO: Capture on the Steam Deck after booting the ISO:
#   1. Build ISO:     nix build .#iso
#   2. Flash to USB and boot Deck from it
#   3. SSH in as root: ssh root@<deck-ip>  (password: nixos)
#   4. Run: nixos-generate-config --show-hardware-config
#   5. Copy the output and replace this file
#
# Placeholder to allow flake evaluation — replace with real hardware config
# before deployment.

_:

{
  nixpkgs.hostPlatform = "x86_64-linux";
}
