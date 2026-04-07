# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{
  pkgs,
  inputs,
  config,
  ...
}:

let
  dns = import ../../lib/dns.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../profiles/workstation/configuration.nix
    ./samba.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/amd.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/android.nix
    ../../modules/nixos/nfs-client.nix
    ../../modules/nixos/openconnect.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/tailscale.nix
    inputs.play-nix.nixosModules.play
    ../../modules/nixos/server/attic-watch-store.nix
  ];

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    secrets.tailscale_authkey = { };
  };

  # Custom modules configuration
  modules = {
    # Mount NFS share from theoden
    nfs-client.enable = true;

    # Tailscale client (not exit node - Mullvad handles regular traffic)
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      excludeFromMullvad = true;
      acceptRoutes = false; # Already on LAN — don't accept subnet routes (avoids routing 192.168.1.0/24 through Tailscale)
      acceptDns = false; # Use AdGuard directly, avoid DNS conflicts with Mullvad
      operator = "ammar";
      useExitNode = null; # Don't route through exit node (Mullvad handles VPN)
    };

    # Mullvad custom DNS (AdGuard instances + fallback)
    privacy.mullvadCustomDns = dns.servers;

    # SSH server
    ssh.enable = true;
  };

  networking = {
    hostName = "ammars-pc";
    nameservers = [ (builtins.head dns.servers) ]; # AdGuard VIP only — router fallback is in services.resolved.fallbackDns
    # Allow Tailscale traffic (100.64.0.0/10) to bypass Mullvad VPN
    # Uses Mullvad's split-tunnel ct mark (0x00000f41) so its firewall
    # treats Tailscale traffic like an excluded app, plus the routing
    # fwmark (0x6d6f6c65) to skip Mullvad's routing table.
    nftables.tables.mullvad-tailscale-bypass = {
      family = "inet";
      content = ''
        chain output {
          type route hook output priority 0; policy accept;
          ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
          ip6 daddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
        }

        chain input {
          type filter hook input priority -100; policy accept;
          ip saddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
          ip6 saddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
        }
      '';
    };
  };
  environment.systemPackages = with pkgs; [
    signal-desktop
    cifs-utils
  ];

  virtualisation.docker.enable = true;

  services = {
    attic-watch-store.enable = true;
    udev.enable = true;
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };
  };

  moondeck = {
    enable = true;
    sunshine.enable = true;
  };

  programs.ssh.knownHosts = {
    "theoden.lan".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAzH8WouJOjPIrJH3ngAxWaSEw6YLDREAbFxIgr7mjX";
    "boromir.lan".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEsPlw7G8qNx5esED6AHc6EQhZk0nuLxfwh1IlZ1k5Nb";
  };

  nix = {
    distributedBuilds = true;
    settings = {
      max-jobs = 0;
      builders-use-substitutes = true;
    };
    buildMachines = [
      {
        hostName = "theoden.lan";
        systems = [ "x86_64-linux" ];
        sshUser = "root";
        sshKey = "/home/ammar/.ssh/id_ed25519";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "big-parallel"
          "kvm"
        ];
      }
      {
        hostName = "boromir.lan";
        systems = [ "x86_64-linux" ];
        sshUser = "root";
        sshKey = "/home/ammar/.ssh/id_ed25519";
        maxJobs = 3;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };

  opendeck.enable = true;

  # Brave browser - disable DoH since OPNsense handles DNS with Mullvad DoT
  programs.brave = {
    enable = true;
    features.sync = true;
    features.aiChat = true;
    doh.enable = false; # Use system DNS (router-level encryption)
  };
}
