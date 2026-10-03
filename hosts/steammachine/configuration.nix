# Steam Machine — Jovian NixOS configuration
#
# Replaces stock SteamOS on the internal NVMe. See
# .agents/plans/2026-09-29-steam-machine-jovian-nixos.md.
#
# Managed Home Manager: one nixos-anywhere run deploys everything.
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
    inputs.jovian-fremont.nixosModules.default
    inputs.home-manager-unstable.nixosModules.home-manager
    ../_profiles/base.nix
    ../_profiles/secrets.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/tailscale.nix
    ../../modules/nixos/networking.nix
  ];

  # ── Jovian Steam Machine ───────────────────────────────────────────
  # No `nixpkgs.overlays` here, deliberately. Importing the Jovian module
  # already applies its overlay: modules/default.nix -> modules/jovian/
  # default.nix -> modules/jovian/overlay.nix sets `nixpkgs.overlays`.
  # Assigning it again runs the overlay twice, and the second pass
  # re-appends patches (e.g. pkgs/mangohud), which breaks the build.
  jovian = {
    devices.steammachine = {
      enable = true;
      # Metadata and the F7F0108.cab payload are hash-pinned by Nix via
      # pkgs.fremont-hw-support, so a network remote cannot be tampered with
      # in transit. Flashing stays manual: autoUpdate is left at its default
      # of false, and a BIOS update cannot be rolled back by a NixOS generation.
      enableFwupdBiosUpdates = true;
    };
    steam = {
      enable = true;
      autoStart = true;
      user = "ammar";
      desktopSession = "plasma";
    };
  };

  # ── Gaming system services (Steam, gamemode, gamescope) ────────────
  # desktop = false drops the desktop Steam extras: gamemode, the NixOS
  # gamescope module, the 8BitDo udev rules and SteamTinkerLaunch. Jovian
  # supplies gamescope with cap_sys_nice, an unfiltered hidraw uaccess rule,
  # and its own performance path.
  #
  # This is the NixOS half of the option. home.nix sets the Home Manager half
  # separately: the two module classes are independent namespaces, so the flag
  # does not carry across on its own.
  gaming = {
    enable = true;
    desktop = false;
  };

  # ── Tailscale mesh VPN (no exit node) ──────────────────────────────
  modules.tailscale = {
    enable = true;
    operator = "ammar";
    useExitNode = null;
  };

  # ── Theoden game archive, read-only ────────────────────────────────
  # Written host-locally rather than via modules/nixos/nfs-client.nix so the
  # shared module keeps its current behaviour for the other hosts. The module
  # hardcodes its mount flags and exposes no read-only option.
  #
  # systemd.mounts, not fileSystems: the automount units fileSystems
  # generates do not support reload, which rolls back deploy-rs activations.
  boot.supportedFilesystems = [ "nfs" ];

  systemd = {
    mounts = [
      {
        what = "theoden.lan:/";
        where = "/mnt/storage";
        type = "nfs";
        options = "nfsvers=4.2,acl,ro";
      }
    ];

    automounts = [
      {
        where = "/mnt/storage";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
        wantedBy = [ "multi-user.target" ];
      }
    ];

    # drkonqi ships drkonqi-coredump-processor@.service with
    # `WantedBy=systemd-coredump@.service`, so every crash pulls it in. It
    # expects a KDE Plasma session socket to report to, but Gaming Mode is a
    # gamescope session, so the socket never connects and it aborts with
    # `QLocalSocket::UnconnectedState`. Its own SIGABRT is itself a coredump,
    # which pulls it in again — a self-feeding loop that produced over 15,000
    # coredumps at roughly 10 per second on first boot.
    #
    # NixOS owns /etc/systemd/system for unit files, so `systemctl mask` cannot
    # be used; suppressedSystemUnits is the declarative equivalent.
    suppressedSystemUnits = [ "drkonqi-coredump-processor@.service" ];
  };

  # ── KDE Plasma 6 for Desktop Mode ──────────────────────────────────
  services = {
    desktopManager.plasma6.enable = true;
    pipewire.alsa.support32Bit = true;
  };

  # ── Programs ──────────────────────────────────────────────────────
  programs = {
    # Jovian supplies its own gamescope session through jovian.steam.
    gamescope.enable = lib.mkForce false;

    # SSH known hosts for LAN
    ssh.knownHosts = {
      "theoden.lan".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAzH8WouJOjPIrJH3ngAxWaSEw6YLDREAbFxIgr7mjX";
      "boromir.lan".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEsPlw7G8qNx5esED6AHc6EQhZk0nuLxfwh1IlZ1k5Nb";
    };
  };

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
  };

  # ── Managed Home Manager — one deploy covers system and user ───────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ./home.nix;
  };

  # ── Secrets ────────────────────────────────────────────────────────
  # Uses the age key from the home directory, like the workstations.
  # Copy it to /home/ammar/.config/sops/age/keys.txt after install.
  sops = {
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    secrets.tailscale_authkey = { };
  };

  # ── Networking ─────────────────────────────────────────────────────
  networking = {
    hostName = "steammachine";
    # Jovian and the Steam UI expect NetworkManager.
    networkmanager.enable = true;

    # The machine sleeps on a power-button event (steamos-powerbuttond, Deck
    # semantics), and while in s2idle it answers no ARP and drops off
    # Tailscale, so it becomes unadministrable until something local wakes it.
    #
    # enp5s0 reports `Supports Wake-on: pumbg` with `Wake-on: d`. The policy
    # default is [ "magic" ], i.e. the magic packet that `wakeonlan` sends:
    #   wakeonlan 90:82:c3:39:05:81
    interfaces.enp5s0.wakeOnLan.enable = true;
  };

  # ethtool is not in the base profile, and it is how you confirm the above
  # worked: `ethtool enp5s0` should report `Wake-on: g`. It writes a systemd
  # .link, so it takes effect when the device appears, not live.
  environment.systemPackages = [ pkgs.ethtool ];

  # ── Bootloader ─────────────────────────────────────────────────────
  # GRUB on the removable path, matching hosts/steamdeck.
  #
  # efibootmgr on the machine shows no explicit OS boot entry — only
  # Boot0001, an {auto_created_boot_option} for the NVMe, which the firmware
  # resolves by scanning for \EFI\BOOT\BOOTX64.EFI. An NVRAM-only install
  # would leave the machine unable to boot.
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
