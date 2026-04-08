# Universal foundation for all NixOS systems
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./ssh.nix
    ./vault-agent.nix
    ./server/attic-watch-store.nix
  ];

  # SSH — all hosts use the same config
  modules.ssh = {
    enable = true;
    permitRootLogin = "prohibit-password";
  };

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

  nixpkgs.hostPlatform = "x86_64-linux";

  environment.systemPackages = with pkgs; [
    wget
    zip
    unzip
    killall
    git
    vim
    openssl
    tree
  ];

  programs = {
    fish.enable = true;
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        SDL2
        glew
        curl
        zlib
        mesa
      ];
    };
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "ammar"
      ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://hyprland.cachix.org"
        "https://claude-code.cachix.org"
        "https://comfyui.cachix.org"
        "https://cache.nixos-cuda.org"
        "https://cache.garnix.io"
        "https://cache.flox.dev"
        "https://pre-commit-hooks.cachix.org"
        # "https://attic.dimensiondoor.xyz/middle-earth" # Attic via Traefik (disabled until K8s routing ready)
        "http://theoden.lan:8080/middle-earth" # Attic direct
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
        "pre-commit-hooks.cachix.org-1:Fh9gmh3LNW5ql37bCKCQ3UPE7AXrBVOeHLiuTJfV7Jo="
        "middle-earth:QJM6g097RUDyZA0OG00fXc7JxFMOXN3J5ZBX8j+QfFI="
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 3d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Chicago";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Trust the homelab LAN CA for .lan domain TLS certificates
  security.pki.certificateFiles = [ ../../certs/lan-ca.crt ];

  # NIX_SSL_CERT_FILE points to the raw Mozilla bundle in /nix/store,
  # which doesn't include custom CAs from security.pki. Override it to
  # use the merged system bundle so Node.js and other tools trust our CA.
  # NODE_EXTRA_CA_CERTS is needed for Bun-based tools (e.g. Claude Code).
  environment.variables = {
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
  };

  networking.firewall = {
    enable = true;
    allowPing = true;
  };

  users.users.ammar = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "dialout" # Serial port access (Zigbee dongles, etc.)
    ];
    shell = pkgs.fish;
  };
}
