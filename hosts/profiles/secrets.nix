# Secrets infrastructure — SOPS bootstrap, vault-agent, and Attic push token
#
# Imported by server and workstation profiles. Not used by the ISO.
{
  config,
  lib,
  ...
}:

{
  imports = [
    ../../modules/nixos/vault-agent.nix
    ../../modules/nixos/server/attic-watch-store.nix
  ];

  # SOPS — bootstrap vault-agent credentials
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
    secrets = {
      vault_role_id = { };
      vault_secret_id = { };
    };
  };

  # Vault agent — fetches secrets from OpenBao on erebor
  modules.vault-agent = {
    enable = lib.mkDefault true;
    address = lib.mkDefault "http://100.64.0.21:8200";
    roleIdFile = config.sops.secrets.vault_role_id.path;
    secretIdFile = config.sops.secrets.vault_secret_id.path;
    secrets = {
      tailscale_authkey = {
        path = "secret/nixos/tailscale";
        field = "authkey";
      };
      attic_push_token = {
        path = "secret/nixos/attic";
        field = "push_token";
      };
    };
  };

  # Attic watch-store — push builds to binary cache
  services.attic-watch-store = {
    enable = lib.mkDefault true;
    useSops = lib.mkDefault false;
    tokenFile = lib.mkDefault "/run/secrets/attic_push_token";
  };
}
