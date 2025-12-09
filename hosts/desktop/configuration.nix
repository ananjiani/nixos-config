# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../profiles/workstation/configuration.nix
    ./samba.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/amd.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/android.nix
    inputs.play-nix.nixosModules.play
  ];

  networking.hostName = "ammars-pc";
  environment.systemPackages = with pkgs; [ signal-desktop ];

  virtualisation.docker.enable = true;
  services.udev = {
    enable = true;
  };

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  moondeck = {
    enable = true;
    sunshine.enable = true;
  };

  opendeck.enable = true;

  modules.ssh.enable = true;
}
