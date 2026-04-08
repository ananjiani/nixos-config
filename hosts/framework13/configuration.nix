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
    ../../modules/nixos/vault-agent.nix
  ];

  # SOPS bootstraps vault-agent credentials; vault-agent fetches application secrets
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    secrets.vault_role_id = { };
    secrets.vault_secret_id = { };
  };

  modules.vault-agent = {
    enable = true;
    address = "http://100.64.0.21:8200"; # Tailscale IP (MagicDNS disabled)
    roleIdFile = config.sops.secrets.vault_role_id.path;
    secretIdFile = config.sops.secrets.vault_secret_id.path;
    secrets = {
      tailscale_authkey = {
        path = "secret/nixos/tailscale";
        field = "authkey";
      };
    };
  };

  modules.tailscale = {
    enable = true;
    loginServer = "https://ts.dimensiondoor.xyz";
    authKeyFile = "/run/secrets/tailscale_authkey";
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
  networking.hostName = "framework13"; # Define your hostname.
}
