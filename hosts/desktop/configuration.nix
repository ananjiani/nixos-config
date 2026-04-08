# ammars-pc — Primary desktop workstation
{
  pkgs,
  inputs,
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
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/android.nix
    ../../modules/nixos/nfs-client.nix
    ../../modules/nixos/openconnect.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/tailscale.nix
    inputs.play-nix.nixosModules.play
  ];

  # Desktop uses age key from home directory (servers use /var/lib/sops-nix/)
  sops.age.keyFile = "/home/ammar/.config/sops/age/keys.txt";

  # Custom modules configuration
  modules = {
    # Mount NFS share from theoden
    nfs-client.enable = true;

    # Tailscale client (not exit node - Mullvad handles regular traffic)
    tailscale = {
      enable = true;
      excludeFromMullvad = true;
      operator = "ammar";
    };

    # Mullvad custom DNS (AdGuard instances + fallback)
    privacy.mullvadCustomDns = dns.servers;
  };

  networking = {
    hostName = "ammars-pc";
    nameservers = [ (builtins.head dns.servers) ]; # AdGuard VIP only — router fallback is in services.resolved.fallbackDns
    # Tailscale bypass is loaded via systemd (see systemd.services.mullvad-tailscale-bypass)
    # because networking.nftables.tables requires networking.nftables.enable which
    # switches the entire firewall backend and breaks iptables-nft rules (Docker, Tailscale).
  };
  # Allow Tailscale traffic (100.64.0.0/10) to bypass Mullvad VPN
  # Uses Mullvad's split-tunnel ct mark (0x00000f41) so its firewall
  # treats Tailscale traffic like an excluded app, plus the routing
  # fwmark (0x6d6f6c65) to skip Mullvad's routing table.
  # Loaded via nft directly because networking.nftables.tables requires
  # networking.nftables.enable which switches the firewall backend.
  systemd.services.mullvad-tailscale-bypass = {
    description = "nftables bypass for Tailscale traffic through Mullvad";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f ${pkgs.writeText "mullvad-tailscale-bypass.nft" ''
        table inet mullvad-tailscale-bypass {
          chain output {
            type route hook output priority -10; policy accept;
            ip daddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
            ip6 daddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
          }

          chain input {
            type filter hook input priority -100; policy accept;
            ip saddr 100.64.0.0/10 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
            ip6 saddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
          }
        }
      ''}";
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet mullvad-tailscale-bypass";
    };
  };

  environment.systemPackages = with pkgs; [
    signal-desktop
    cifs-utils
  ];

  virtualisation.docker.enable = true;

  services.udev.enable = true;
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
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
