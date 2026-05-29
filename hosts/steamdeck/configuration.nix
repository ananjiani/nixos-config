# Steam Deck — Jovian NixOS configuration
#
# Managed Home Manager: one `nixos-rebuild --target-host` deploys everything.
# No separate `nh home switch` needed.
{
  pkgs,
  lib,
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    inputs.jovian.nixosModules.jovian
    inputs.chaotic.nixosModules.default
    inputs.home-manager-unstable.nixosModules.home-manager
    ../_profiles/base.nix
    ../_profiles/secrets.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/nfs-client.nix
  ];

  # ── Jovian Steam Deck ──────────────────────────────────────────────
  jovian = {
    devices.steamdeck.enable = true;
    steam = {
      enable = true;
      autoStart = true;
      user = "ammar";
      desktopSession = "plasma";
    };
  };

  # ── Gaming system services (Steam, gamemode, gamescope) ────────────
  # Disable NixOS gamescope — Jovian's steam module provides its own wrapper
  gaming.enable = true;

  # ── Tailscale mesh VPN (no exit node on Deck) ──────────────────────
  modules.tailscale = {
    enable = true;
    operator = "ammar";
    useExitNode = null;
  };

  # ── NFS client — mount theoden game library at /mnt/storage ────────
  modules.nfs-client = {
    enable = true;
    mountPoint = "/mnt/storage";
    server = "theoden.lan";
  };

  # ── KDE Plasma 6 for Desktop Mode ──────────────────────────────────
  services = {
    desktopManager.plasma6.enable = true;
    # PipeWire 32-bit ALSA support (Jovian handles the rest)
    pipewire.alsa.support32Bit = true;
  };

  # ── Programs ──────────────────────────────────────────────────────
  programs = {
    # Disable NixOS gamescope — Jovian's steam module provides its own wrapper
    gamescope.enable = lib.mkForce false;

    # Brave browser (declarative, syncs with desktop)
    brave = {
      enable = true;
      package = pkgs.brave-origin;
      features.sync = true;
      doh.enable = false; # Use system DNS (router-level encryption)
      searchEngine = {
        enable = true;
        searchUrl = "https://searxng.lan/search?q={searchTerms}";
        suggestUrl = "https://searxng.lan/autocompleter?q={searchTerms}";
      };
    };

    # SSH known hosts for LAN
    ssh.knownHosts = {
      "theoden.lan".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAzH8WouJOjPIrJH3ngAxWaSEw6YLDREAbFxIgr7mjX";
      "boromir.lan".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEsPlw7G8qNx5esED6AHc6EQhZk0nuLxfwh1IlZ1k5Nb";
    };
  };

  # ── PipeWire 32-bit ALSA support (Jovian handles the rest) ─────────

  # ── Firmware ───────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;

  # ── User ───────────────────────────────────────────────────────────
  users.users.ammar = {
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
    initialPassword = "temp";
  };

  # ── Managed Home Manager — one nixos-rebuild deploys everything ────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # ── Secrets ────────────────────────────────────────────────────────
  # Deck uses age key from home directory (same as workstations)
  sops.age.keyFile = "/home/ammar/.config/sops/age/keys.txt";

  # ── Networking ─────────────────────────────────────────────────────
  networking = {
    hostName = "steamdeck";
    # Required by Jovian/Steam Deck UI for first-time setup
    networkmanager.enable = true;
  };

  # ── Bootloader (GRUB + EFI — Steam Deck standard) ─────────────────
  boot.loader = {
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      efiInstallAsRemovable = true;
    };
  };

  system.stateVersion = "25.11";
}
