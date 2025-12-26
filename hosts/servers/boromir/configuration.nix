# Boromir - Proxmox VM (minimal base)
{
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ./disk-config.nix
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/ssh.nix
    ../../../modules/nixos/nfs-client.nix
    ../../../modules/nixos/networking.nix
    ../../../modules/nixos/caddy.nix
    ../../../modules/nixos/headscale.nix
    ../../../modules/nixos/tailscale.nix
  ];

  modules = {
    # Mount NFS share from faramir (use IP since we ARE the DNS server)
    nfs-client = {
      enable = true;
      server = "192.168.1.22";
    };

    # Caddy reverse proxy (handles TLS via Let's Encrypt)
    caddy = {
      enable = true;
      email = "ammar@dimensiondoor.xyz"; # For Let's Encrypt
      virtualHosts = {
        "ts.dimensiondoor.xyz" = "localhost:8080";
        # Add more services here as needed
      };
    };

    # Headscale - self-hosted Tailscale control server
    headscale = {
      enable = true;
      domain = "ts.dimensiondoor.xyz";
      baseDomain = "tail.dimensiondoor.xyz";
    };

    # Tailscale client - this node is an exit node
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      exitNode = true;
    };

    # SSH server
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };

  networking = {
    hostName = "boromir";
    useDHCP = true;
    firewall.allowedUDPPorts = [ 53 ];
    firewall.allowedTCPPorts = [ 53 ];
  };

  # AdGuard Home - Network-wide DNS with ad blocking
  services.adguardhome = {
    enable = true;
    openFirewall = true; # Opens port 53 (DNS) and 3000 (web UI)
    mutableSettings = false; # Fully declarative - UI changes don't persist
    settings = {
      http = {
        address = "0.0.0.0:3000";
      };
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "1.1.1.1" # Cloudflare (fast, privacy-focused)
          "9.9.9.9" # Quad9 (blocks malware, no logging)
          "194.242.2.2" # Mullvad (privacy-focused)
        ];
        bootstrap_dns = [
          "1.1.1.1"
          "9.9.9.9"
        ];
      };
      filtering = {
        rewrites = [
          {
            domain = "faramir.lan";
            answer = "192.168.1.22";
            enabled = true;
          }
          {
            domain = "boromir.lan";
            answer = "192.168.1.21";
            enabled = true;
          }
          {
            domain = "gondor.lan";
            answer = "192.168.1.20";
            enabled = true;
          }
          {
            domain = "the-shire.lan";
            answer = "192.168.1.23";
            enabled = true;
          }
          {
            domain = "rohan.lan";
            answer = "192.168.1.24";
            enabled = true;
          }
          {
            domain = "frodo.lan";
            answer = "192.168.1.25";
            enabled = true;
          }
          {
            domain = "samwise.lan";
            answer = "192.168.1.26";
            enabled = true;
          }
          {
            domain = "router.lan";
            answer = "192.168.1.1";
            enabled = true;
          }
          # Headscale - local resolution to avoid hairpin NAT
          {
            domain = "ts.dimensiondoor.xyz";
            answer = "192.168.1.21";
            enabled = true;
          }
        ];
      };
    };
  };

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # Proxmox VM integration
  services.qemuGuest.enable = true;

  # Boot configuration (GRUB for BIOS)
  # Note: disko sets grub.devices automatically from disk-config.nix
  boot = {
    loader.grub.enable = true;
    # Virtio modules for Proxmox
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
