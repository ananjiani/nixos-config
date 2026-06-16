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
      acceptDns = true; # Use Headscale split DNS for dimensiondoor.xyz → AdGuard
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
  programs = {

    nm-applet.enable = true;
    brave = {
      enable = true;
      package = pkgs.brave-origin;
      features.sync = true;
      features.aiChat = true;
      doh.enable = false;
      searchEngine = {
        enable = true;
        searchUrl = "https://searxng.lan/search?q={searchTerms}";
        suggestUrl = "https://searxng.lan/autocompleter?q={searchTerms}";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    brightnessctl
    brave # fallback during brave-origin transition
  ];

  # Backlight control requires the video group
  users.users.ammar.extraGroups = [ "video" ];
  # Disable systemd-backlight — it saves/restores backlight values that
  # can get stuck at extremely low brightness (e.g. 5%) on Framework 13
  # AMD, and the stale state persists across reboots.
  systemd.services."systemd-backlight@backlight:amdgpu_bl1".enable = false;

  networking.hostName = "framework13";
}
