# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{
  pkgs,
  inputs,
  config,
  ...
}:

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
    ../../modules/nixos/networking.nix
    ../../modules/nixos/tailscale.nix
    inputs.play-nix.nixosModules.play
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
      acceptDns = false; # Use AdGuard directly, avoid DNS conflicts with Mullvad
    };

    # Mullvad custom DNS (AdGuard + router fallback)
    privacy.mullvadCustomDns = [
      "192.168.1.53" # AdGuard
      "192.168.1.1" # Router fallback
    ];

    # SSH server
    ssh.enable = true;
  };

  networking.hostName = "ammars-pc";

  # Allow Tailscale traffic (100.64.0.0/10) to bypass Mullvad VPN
  # Mullvad's LAN sharing only covers RFC1918 ranges, not CGNAT
  networking.nftables.tables.mullvad-tailscale-bypass = {
    family = "inet";
    content = ''
      chain output {
        type route hook output priority -150; policy accept;
        ip daddr 100.64.0.0/10 mark set 0x6d6f6c65
        ip6 daddr fd7a:115c:a1e0::/48 mark set 0x6d6f6c65
      }
    '';
  };
  environment.systemPackages = with pkgs; [ signal-desktop ];

  virtualisation.docker.enable = true;
  services.udev = {
    enable = true;
  };

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

  opendeck.enable = true;

  # Brave browser - disable DoH since OPNsense handles DNS with Mullvad DoT
  programs.brave = {
    enable = true;
    features.sync = true;
    features.aiChat = true;
    doh.enable = false; # Use system DNS (router-level encryption)
  };
}
