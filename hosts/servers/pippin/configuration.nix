# Pippin - Clawdbot AI Assistant (Proxmox VM on the-shire)
#
# Dedicated isolated VM for clawdbot to safely execute arbitrary commands.
# Uses npm-based installation for simplicity and small footprint.
{
  inputs,
  pkgs-stable,
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/tailscale.nix
    ../../../modules/nixos/server/attic-watch-store.nix
  ];

  networking = {
    hostName = "pippin";
    useDHCP = true;
    nameservers = [
      "192.168.1.53" # AdGuard VIP with internal DNS rewrites
      "9.9.9.9" # Quad9 fallback
    ];
    # Allow clawdbot web UI access
    firewall.allowedTCPPorts = [ 18789 ];
  };

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      tailscale_authkey = { };
      telegram_bot_token = { };
      bifrost_api_key = { };
    };
    # Environment file for clawdbot service
    templates."clawdbot.env" = {
      content = ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.telegram_bot_token}
        ANTHROPIC_API_KEY=${config.sops.placeholder.bifrost_api_key}
      '';
    };
  };

  modules = {
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      acceptDns = false;
      acceptRoutes = false;
      useExitNode = null; # On LAN, no exit node needed
    };

    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Node.js for clawdbot
  environment.systemPackages = with pkgs; [
    nodejs_22
    git # Required by clawdbot installer
  ];

  # Clawdbot data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/clawdbot 0755 root root -"
    "d /var/lib/clawdbot/.npm-global 0755 root root -"
  ];

  # Clawdbot systemd service
  systemd.services.clawdbot = {
    description = "Clawdbot AI Assistant";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/var/lib/clawdbot";
      NPM_CONFIG_PREFIX = "/var/lib/clawdbot/.npm-global";
      # Skip native libvips build (uses JS fallback)
      SHARP_IGNORE_GLOBAL_LIBVIPS = "1";
      # Gateway auth token for LAN binding (required by clawdbot)
      CLAWDBOT_GATEWAY_TOKEN = "pippin-gateway-token";
    };

    path = [
      pkgs.nodejs_22
      pkgs.git
      pkgs.coreutils
      pkgs.bash
      pkgs.gnused
      pkgs.gnugrep
      pkgs.gawk
    ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/var/lib/clawdbot";
      EnvironmentFile = config.sops.templates."clawdbot.env".path;

      # Allow 10 minutes for initial npm install
      TimeoutStartSec = "10min";

      # Install and setup clawdbot
      ExecStartPre = [
        (pkgs.writeShellScript "clawdbot-install" ''
          set -euo pipefail
          export PATH=/var/lib/clawdbot/.npm-global/bin:$PATH

          if [ ! -x /var/lib/clawdbot/.npm-global/bin/clawdbot ]; then
            echo "Installing clawdbot..."
            npm install -g clawdbot@latest
          fi
        '')
        (pkgs.writeShellScript "clawdbot-setup" ''
          set -euo pipefail
          export PATH=/var/lib/clawdbot/.npm-global/bin:$PATH

          # Only run doctor --fix on first setup (when telegram isn't configured)
          CONFIG="$HOME/.clawdbot/clawdbot.json"
          if [ ! -f "$CONFIG" ] || ! grep -q '"telegram"' "$CONFIG" 2>/dev/null; then
            echo "Running initial clawdbot setup..."
            clawdbot doctor --fix --non-interactive || true
          fi
        '')
      ];

      ExecStart = "/var/lib/clawdbot/.npm-global/bin/clawdbot gateway --port 18789 --bind lan --allow-unconfigured";

      Restart = "on-failure";
      RestartSec = "10s";

      # Security hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ "/var/lib/clawdbot" ];
    };
  };

  services = {
    qemuGuest.enable = true;
    attic-watch-store.enable = true;
  };

  boot = {
    loader.grub.enable = true;
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "virtio_net"
      "sd_mod"
    ];
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
