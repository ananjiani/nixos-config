# Framework 13 — Laptop workstation
{
  pkgs,
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

  environment.systemPackages = with pkgs; [ networkmanagerapplet ];
  # Block power-profiles-daemon from using amdgpu_panel_power, which
  # can kill the backlight on Framework 13 AMD via ABM (adaptive
  # backlight management).  See:
  # https://community.frame.work/t/framework-nixos-linux-users-self-help/31426/280
  systemd.services.power-profiles-daemon.serviceConfig.ExecStart = [
    ""
    "${pkgs.power-profiles-daemon}/libexec/power-profiles-daemon --block-action=amdgpu_panel_power"
  ];

  networking.hostName = "framework13";
}
