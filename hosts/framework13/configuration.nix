# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{
  pkgs,
  config,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../profiles/workstation/configuration.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/wm.nix
    ../../modules/nixos/utils.nix
    # ../../modules/nixos/openconnect.nix
    ../../modules/nixos/docker.nix
    ../../modules/nixos/tailscale.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    secrets.tailscale_authkey = { };
  };

  modules.tailscale = {
    enable = true;
    loginServer = "https://ts.dimensiondoor.xyz";
    authKeyFile = config.sops.secrets.tailscale_authkey.path;
    excludeFromMullvad = true;
  };
  programs = {

    nm-applet.enable = true;
    brave = {
      enable = true;
      features.sync = true;
      features.aiChat = true;
      doh.enable = false;
    };
  };

  environment.systemPackages = with pkgs; [ networkmanagerapplet ];
  networking.hostName = "framework13"; # Define your hostname.
}
