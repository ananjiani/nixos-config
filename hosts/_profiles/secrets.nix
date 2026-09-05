# Secrets infrastructure — SOPS bootstrap, vault-agent, Attic, and NixCI cache
#
# Imported by server and workstation profiles and steamdeck.
# Not used by the ISO, WSL, or denethor (no SOPS; do not leak cache.nix-ci.com).
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

  # SOPS — vault-agent bootstrap and NixCI netrc (root-only)
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
    secrets = {
      vault_role_id = { };
      vault_secret_id = { };
      nix_ci_netrc = {
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };

  # NixCI authenticated cache. Priority 50: after Attic (10) and cache.nixos.org (40).
  nix.settings = {
    extra-substituters = [ "https://cache.nix-ci.com?priority=50" ];
    extra-trusted-public-keys = [ "nix-ci:g3xV5BDTLtIBZr/A00IU1x0EtKKlb7YLgBN2SgYgM6A=" ];
    netrc-file = config.sops.secrets.nix_ci_netrc.path;
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
    upstreamCacheKeyNames = [
      "cache.nixos.org-1"
      "nix-community.cachix.org-1"
      "hyprland.cachix.org-1"
      "pre-commit-hooks.cachix.org-1"
    ];
  };
}
