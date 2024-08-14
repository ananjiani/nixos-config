{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ../../modules/nixos/utils.nix ];

  networking.hostName = "router";
  services.openssh = {
    enable = true;
    passwordAuthentication = true;
  };

}
