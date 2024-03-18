{ config, lib, pkgs, sops-nix, ... }:

{
  imports = [
    sops-nix.homeManagerModules.sops
  ];

  sops = {
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    defaultSopsFile = ../../../secrets/secrets.yaml;
    defaultSymlinkPath = "/run/user/1000/secrets";
    defaultSecretsMountPoint = "/run/user/1000/secrets.d";
    secrets.atuin_key.sopsFile = ../../../secrets/secrets.yaml; 
  };

  home.activation.setupEtc = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    /run/current-system/sw/bin/systemctl start --user sops-nix
  '';
}
