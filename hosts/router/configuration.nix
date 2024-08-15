{ config, lib, pkgs, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ../../modules/nixos/utils.nix ];

  networking.hostName = "router";
  services.openssh = { enable = true; };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoo8KQiLBJ6WrWmG0/6O8lww/v6ggPaLfv70/ksMZbD ammar.nanjiani@gmail.com"
  ];
  services.proxmox-ve.enable = true;
  nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.x86_64-linux ];
}
