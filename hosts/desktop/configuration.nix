# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{
  pkgs,
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
  ];

  networking.hostName = "ammars-pc";
  environment.systemPackages = with pkgs; [ signal-desktop ];

  virtualisation.docker.enable = true;
  services.udev = {
    enable = true;
    packages = with pkgs; [ android-udev-rules ];
  };

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
  };

}
