# wsl-work - NixOS-WSL (work laptop, Windows host)
#
# Runs under WSL2 alongside Windows OpenSSH on port 22, so the guest
# listener moves to 2222. No LAN reachability to the homelab Attic
# cache, so substitute via the public Cloudflare Tunnel like erebor.
{ ... }:

{
  imports = [
    ../_profiles/base.nix
  ];

  wsl = {
    enable = true;
    defaultUser = "ammar";
  };

  # Avoid collision with Windows OpenSSH on port 22
  services.openssh.ports = [ 2222 ];

  # Attic cache via Cloudflare Tunnel — mirrors erebor (LAN cache theoden.lan
  # unreachable from WSL). The middle-earth public key is trusted via base.nix.
  nix.settings.extra-substituters = [ "https://attic.dimensiondoor.xyz/middle-earth?priority=10" ];

  networking.hostName = "wsl-work";

  system.stateVersion = "25.11";
}
