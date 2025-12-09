In project directory:

```bash
# Apply NixOS system configuration
nh os switch

# Apply Home Manager configuration
nh home switch

# Build the live USB / installation ISO
nix build .#nixosConfigurations.iso.config.system.build.isoImage
# The ISO will be at result/iso/nixos-*.iso
```
