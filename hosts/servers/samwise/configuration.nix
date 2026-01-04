# Samwise - Zigbee2MQTT and MQTT Broker (Proxmox VM on the-shire)
#
# This VM hosts:
# - Mosquitto MQTT broker (port 1883)
# - zigbee2mqtt with SONOFF Zigbee dongle (frontend on port 8080)
#
# Home Assistant (frodo) connects to Mosquitto for device control via MQTT.
{
  inputs,
  pkgs-stable,
  config,
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
    ../../../modules/nixos/server/zigbee2mqtt.nix
    ../../../modules/nixos/server/k3s.nix
  ];

  networking = {
    hostName = "samwise";
    useDHCP = true;
    firewall.allowedTCPPorts = [
      1883 # MQTT
    ];
  };

  # SOPS secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.k3s_token = { };
    secrets.tailscale_authkey = { };
  };

  modules = {
    # k3s server node (joins existing cluster)
    k3s = {
      enable = true;
      role = "server";
      clusterInit = false;
      serverAddr = "https://192.168.1.21:6443"; # boromir
      tokenFile = config.sops.secrets.k3s_token.path;
    };

    # Tailscale client - exit node through Mullvad
    tailscale = {
      enable = true;
      loginServer = "https://ts.dimensiondoor.xyz";
      authKeyFile = config.sops.secrets.tailscale_authkey.path;
      exitNode = true;
    };

    # Zigbee2MQTT configuration
    zigbee2mqtt = {
      enable = true;
      mqttServer = "mqtt://localhost:1883";
      frontendPort = 8080;
      # USB device path - verify with: ls -la /dev/serial/by-id/
      serialPort = "/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20230605144345-if00";
      adapter = "ember"; # For SONOFF ZBDongle-E (V2) with EFR32MG21
    };

    # SSH server
    ssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };

  # Mosquitto MQTT broker
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        address = "0.0.0.0";
        settings = {
          allow_anonymous = true; # For initial setup; add auth later
        };
        acl = [ "topic readwrite #" ];
      }
    ];
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

  # USB/serial access for Zigbee dongle
  users.users.ammar.extraGroups = [ "dialout" ];

  system.stateVersion = "25.11";
  nixpkgs.hostPlatform = "x86_64-linux";
}
