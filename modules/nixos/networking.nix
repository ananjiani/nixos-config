{
  lib,
  pkgs-stable,
  ...
}:

let
  lanHosts = import ../../lib/hosts.nix;
in
{
  environment.systemPackages = with pkgs-stable; [
    nftables
    dig
  ];

  # Local network hosts for faster resolution (backup to AdGuard DNS)
  # Derived from lib/hosts.nix — the canonical LAN host → IP map
  networking.hosts = lib.mapAttrs' (name: ip: {
    name = ip;
    value = [
      name
      "${name}.lan"
    ];
  }) lanHosts;
}
