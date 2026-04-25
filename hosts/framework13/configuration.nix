# Framework 13 — Laptop workstation
{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../_profiles/workstation/configuration.nix
    ../../modules/nixos/bluetooth.nix
    # ../../modules/nixos/openconnect.nix
    ../../modules/nixos/docker.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/nfs-client.nix
    ../../modules/nixos/tailscale.nix
  ];

  # Laptop uses age key from home directory (servers use /var/lib/sops-nix/)
  sops.age.keyFile = "/home/ammar/.config/sops/age/keys.txt";

  # Kernel 6.14+ introduced a custom brightness curve that makes the
  # Framework 13 AMD panel extremely dim.  Combine with the existing
  # nixos-hardware PSR disable (0x10) by OR-ing in 0x40000.
  # https://community.frame.work/t/solved-screen-very-dim-with-kernel-6-15-0/69780
  boot.kernelParams = lib.mkAfter [ "amdgpu.dcdebugmask=0x40010" ];

  desktop.niri.enable = true;

  modules = {
    tailscale = {
      enable = true;
      excludeFromMullvad = true;
      operator = "ammar";
    };
    nfs-client.enable = true;
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
  programs = {

    nm-applet.enable = true;
    brave = {
      enable = true;
      features.sync = true;
      features.aiChat = true;
      doh.enable = false;
    };
  };

  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    brightnessctl
  ];

  # Backlight control requires the video group
  users.users.ammar.extraGroups = [ "video" ];
  # Disable systemd-backlight — it saves/restores backlight values that
  # can get stuck at extremely low brightness (e.g. 5%) on Framework 13
  # AMD, and the stale state persists across reboots.
  systemd.services."systemd-backlight@backlight:amdgpu_bl1".enable = false;

  networking.hostName = "framework13";
}
