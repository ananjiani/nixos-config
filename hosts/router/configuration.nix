{ config, lib, pkgs, ... }:

{
  imports = [ ../../modules/nixos/utils.nix ];

  networking.hostName = "router";

}
