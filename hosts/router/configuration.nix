{ config, lib, pkgs, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ../../modules/nixos/utils.nix ];

  networking.hostName = "router";
  services.openssh = {
    enable = true;
    passwordAuthentication = true;
  };
  nix.settings = {
    substituters = [ "https://cache.saumon.network/proxmox-nixos" ];
    trusted-public-keys =
      [ "proxmox-nixos:nveXDuVVhFDRFx8Dn19f1WDEaNRJjPrF2CPD2D+m1ys=" ];
  };
    #services.proxmox-ve.enable = true;
    #nixpkgs.overlays = [
    #  inputs.proxmox-nixos.overlays.${system}
    #];
}
