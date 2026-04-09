# Framework 13 — Laptop workstation
{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../_profiles/workstation/configuration.nix
    ../../modules/nixos/bluetooth.nix
    # ../../modules/nixos/openconnect.nix
    ../../modules/nixos/docker.nix
    ../../modules/nixos/tailscale.nix
  ];

  # Laptop uses age key from home directory (servers use /var/lib/sops-nix/)
  sops.age.keyFile = "/home/ammar/.config/sops/age/keys.txt";

  modules.tailscale = {
    enable = true;
    excludeFromMullvad = true;
    operator = "ammar";
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
  networking.hostName = "framework13";
}
