# Universal foundation for all NixOS systems
#
# Secrets infrastructure (SOPS, vault-agent, attic) lives in secrets.nix,
# imported by server and workstation profiles but not the ISO.
{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/nixos/ssh.nix
  ];

  # SSH — all hosts use the same config
  modules.ssh = {
    enable = true;
    permitRootLogin = lib.mkDefault "prohibit-password";
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
    nh = {
      enable = true;
      flake = "~/.dotfiles";
    };
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        SDL2
        glew
        curl
        zlib
        mesa
        stdenv.cc.cc.lib # libstdc++.so.6 — needed by precompiled binaries (e.g. Vulkan layers)
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
        "https://doom-emacs-unstraightened.cachix.org"
        "https://hyprland.cachix.org"
        "https://claude-code.cachix.org"
        "https://comfyui.cachix.org"
        "https://cache.garnix.io"
        "https://cache.flox.dev"
        "https://pre-commit-hooks.cachix.org"
        # "https://attic.dimensiondoor.xyz/middle-earth" # Attic via Traefik (disabled until K8s routing ready)
        "http://theoden.lan:8080/middle-earth?priority=10" # Attic direct (override server priority 41 so LAN cache beats cache.nixos.org=40)
        "https://nyx-cache.chaotic.cx/"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "doom-emacs-unstraightened.cachix.org-1:O5oOlRPnmQEvVaFyuMTmthCEooHbrg54WgSLR07tmg4="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
        "pre-commit-hooks.cachix.org-1:Fh9gmh3LNW5ql37bCKCQ3UPE7AXrBVOeHLiuTJfV7Jo="
        "middle-earth:QJM6g097RUDyZA0OG00fXc7JxFMOXN3J5ZBX8j+QfFI="
        "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
      ];
      # Substitution tuning
      http-connections = 50;
      max-substitution-jobs = 32;
      connect-timeout = 5;
      download-attempts = 3;
      # If a substituter errors out, route around it instead of failing the
      # whole switch. Source builds get dispatched to remote builders via
      # distributedBuilds, so this is safe even with max-jobs = 0.
      fallback = true;
      narinfo-cache-negative-ttl = 86400;

      # Let derivations that do build locally (preferLocalBuild) use all cores.
      # On workstations max-jobs = 0 keeps real builds remote; on builders this
      # lets each parallel job greedily use available CPU.
      cores = 0;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 3d";
    };
    # Run store deduplication on a timer instead of auto-optimise-store=true,
    # which hardlinks during builds and blocks them.
    optimise = {
      automatic = true;
      dates = [ "03:45" ];
    };
  };

  # Persistent timers fire immediately on wake-from-sleep if they missed
  # their slot; a full-store rehash then saturates the disk (IO PSI ~60%,
  # 2026-07-13). Idle scheduling keeps it from starving interactive I/O.
  # Note: only honored by schedulers with priority classes (bfq); NVMe
  # defaults to "none", where this is best-effort.
  systemd.services.nix-optimise.serviceConfig = {
    IOSchedulingClass = "idle";
    CPUSchedulingPolicy = "idle";
  };

  nixpkgs.config.allowUnfree = true;

  # Cap journald to prevent disk-pressure on servers with large root FS.
  # Theoden accumulated 4.1G over 60 days with no limit, contributing to
  # kubelet disk-pressure taint (see postmortem 2026-05-01).
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=30day
  '';

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

  # DNS: LAN-only by default so AdGuard split-DNS rewrites always win.
  # Mixing a public resolver (Quad9/Cloudflare) here poisons systemd-resolved's
  # global scope: it can select the public server as "current", then NXDOMAIN
  # answers for split-DNS names (e.g. ssh.git.dimensiondoor.xyz, ts.dimensiondoor.xyz)
  # race ahead of AdGuard's rewrite and break things like git-over-SSH and
  # Tailscale login. Erebor overrides this with public DNS because it's a VPS
  # with no LAN reachability to AdGuard. See postmortems 2026-04-07 and
  # 2026-04-10 for the Mullvad-DNS variant of this same footgun.
  networking.nameservers = lib.mkDefault [
    "192.168.1.53" # HA VIP (keepalived AdGuard)
    "192.168.1.1" # OPNsense router (AdGuard upstream)
  ];

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
