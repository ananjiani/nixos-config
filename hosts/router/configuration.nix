{ config, lib, pkgs, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ../../modules/nixos/utils.nix ];

  networking.hostName = "router";
  services.openssh = {
    enable = true;
    passwordAuthentication = true;
  };
  services.proxmox-ve.enable = true;
  nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.x86_64-linux ];
}
