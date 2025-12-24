# Boromir - Proxmox VM (minimal base)
{
  inputs,
  pkgs,
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
    # ../../../modules/nixos/networking.nix
  ];

  environment.systemPackages = with pkgs-stable; [
    nftables
    dig
  ];
  # Mount NFS share from faramir (use IP since we ARE the DNS server)
  modules.nfs-client = {
    enable = true;
    server = "192.168.1.22";
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
          { domain = "faramir.lan"; answer = "192.168.1.22"; enabled = true; }
          { domain = "boromir.lan"; answer = "192.168.1.21"; enabled = true; }
          { domain = "gondor.lan"; answer = "192.168.1.20"; enabled = true; }
          { domain = "router.lan"; answer = "192.168.1.1"; enabled = true; }
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

  # Enable SSH module (permitRootLogin for nixos-anywhere deployment)
  modules.ssh = {
    enable = true;
    permitRootLogin = "prohibit-password";
  };

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
