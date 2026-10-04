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
  # Do not declare the Jovian overlay here. Importing the Jovian module
  # already applies it: modules/default.nix -> modules/jovian/default.nix
  # -> modules/jovian/overlay.nix sets `nixpkgs.overlays`. Assigning it
  # again runs the overlay twice, and the second pass re-appends patches
  # (e.g. pkgs/mangohud), which breaks the build. Only our own overlay
  # belongs in the list further down.
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

  # ── BlueZ: Valve's Switch Pro Controller fix ───────────────────────
  # Valve patches BlueZ on SteamOS so the Nintendo Switch Pro Controller
  # (057e:2009) stops dropping its Bluetooth link. None of it is upstream: it
  # went to review as bluez/bluez#2480 and was closed unmerged, so no BlueZ
  # release will ever carry it and an upgrade will never deliver it. The patch
  # adds BT_IO_OPT_FORCE_ACTIVE and, for this one controller's interrupt
  # channel, sets BT_POWER_FORCE_ACTIVE_OFF — it stops forcing the link out of
  # sniff mode on every outgoing packet.
  #
  # It is written against 5.83 but all 15 hunks apply to the 5.87 source
  # nixpkgs pins, with zero fuzz. It is fetched and extracted from Valve's own
  # source archive rather than vendored, so its provenance stays visible.
  # btio is compiled into bluetoothd and not into libbluetooth, so the change
  # is daemon-side only and alters no ABI.
  #
  # hardware.bluetooth.package is pinned explicitly, below, so that a later
  # override of that option cannot silently drop the patch.
  nixpkgs.overlays = [
    (final: prev: {
      bluez = prev.bluez.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (final.runCommand "bluez-nintendo-force-active.patch"
            {
              src = final.fetchurl {
                url = "https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/holo-3.8/bluez-5.83-1.4.src.tar.gz";
                hash = "sha256-f+LwtPDnNy9/Xp2tRm+Om2/P6euLmIG6Qpbsb91LUgc=";
              };
              nativeBuildInputs = [
                final.gnutar
                final.gzip
              ];
            }
            ''
              tar -xOf "$src" \
                bluez/0024-Modify-Nintendo-gamepad-abnormal-disconnect-during-use.patch > "$out"
            ''
          )
        ];
      });
    })
  ];

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

    # The Steam Machine's Bluetooth radio is an integrated Valve USB device
    # (28de:1401). btusb enables USB autosuspend by default and this adapter
    # genuinely sleeps: one boot showed it suspended 3,238,298 ms against
    # 4,053,263 ms active. Waking it mid-session tears down the radio link
    # ("Bluetooth: hci0: ACL packet for unknown connection handle 2"), which
    # made an external controller drop and re-pair every few minutes.
    #
    # The Steam Controller's own puck arrives with power/control already "on",
    # which is why it was never affected. Nothing declarative sets that, so pin
    # the Bluetooth radio here rather than relying on the same accident.
    udev = {
      extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="1401", TEST=="power/control", ATTR{power/control}="on"
      '';
    };
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

  # ── Hardware ───────────────────────────────────────────────────────
  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;

    # Pinned to the overlaid pkgs.bluez so that a later override of this option
    # cannot silently drop Valve's controller patch. See `nixpkgs.overlays`.
    bluetooth.package = pkgs.bluez;
  };

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
