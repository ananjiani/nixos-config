# Server profile — shared by all server hosts
# (boromir, samwise, theoden, erebor, rivendell)
{
  config,
  lib,
  inputs,
  pkgs-stable,
  ...
}:

{
  options.modules.proxmoxGuest = lib.mkEnableOption "Proxmox VM guest (GRUB + virtio + qemu-guest-agent)";

  imports = [
    inputs.home-manager-unstable.nixosModules.home-manager
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/server/adguard.nix
    ../../modules/nixos/server/keepalived.nix
  ];

  config = {
    # Server defaults — override per-host as needed
    modules = {
      proxmoxGuest = lib.mkDefault true;

      # Most servers are Tailscale exit nodes with LAN subnet routing
      tailscale = {
        enable = lib.mkDefault true;
        exitNode = lib.mkDefault true;
        subnetRoutes = lib.mkDefault [ "192.168.1.0/24" ];
      };
    };
    # Prometheus node exporter for monitoring
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      openFirewall = true;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };

    # Home Manager — shared server config
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs pkgs-stable; };
      users.ammar = import ../servers/home.nix;
    };

    # Proxmox VM: GRUB boot, virtio drivers, qemu-guest-agent
    boot = lib.mkIf config.modules.proxmoxGuest {
      loader.grub.enable = true;
      initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_scsi"
        "virtio_blk"
        "virtio_net"
        "sd_mod"
      ];
    };
    services.qemuGuest.enable = lib.mkDefault config.modules.proxmoxGuest;

    # Default networking: DHCP with Kea reservations (all servers have static leases)
    networking.useDHCP = lib.mkDefault true;

    system.stateVersion = "25.11";
  };
}
