# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../default/configuration.nix
    ../../modules/nixos/wm.nix
    ../../modules/nixos/utils.nix
    ../../modules/nixos/bluetooth.nix
  ];

  networking.hostName = "surface-go"; # Define your hostname.

}
