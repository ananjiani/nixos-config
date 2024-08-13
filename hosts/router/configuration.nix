{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-confiiguration.nix ../../modules/nixos/utils.nix ];

  networking.hostName = "router";

}
