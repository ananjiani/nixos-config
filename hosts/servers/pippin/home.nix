# Pippin Home Manager configuration
#
# Minimal config - clawdbot runs as a system container via quadlet-nix.
{ ... }:

{
  imports = [
    ../../../hosts/profiles/essentials/home.nix
  ];
}
