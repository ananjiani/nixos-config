# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, lib, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../default/configuration.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/wm.nix
    ../../modules/nixos/utils.nix
    ../../modules/nixos/openconnect.nix
    ../../modules/nixos/docker.nix
  ];

  programs.nm-applet.enable = true;
  environment.systemPackages = with pkgs; [ networkmanagerapplet ];
  networking.hostName = "framework13"; # Define your hostname.
}

