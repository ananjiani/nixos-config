{
  config,
  inputs,
  ...
}:

{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    defaultSopsFile = ../../../secrets/secrets.yaml;
    defaultSymlinkPath = "/run/user/1000/secrets";
    defaultSecretsMountPoint = "/run/user/1000/secrets.d";
    secrets = {
      atuin_key.sopsFile = ../../../secrets/secrets.yaml;
      hf_token.sopsFile = ../../../secrets/secrets.yaml;
      proton_bridge_password = {
        sopsFile = ../../../secrets/secrets.yaml;
        mode = "0400";
      };
    };
  };

  home.activation.setupEtc = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    /run/current-system/sw/bin/systemctl start --user sops-nix
  '';
}
