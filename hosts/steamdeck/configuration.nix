# Steam Deck — Jovian NixOS configuration
#
# Managed Home Manager: one `nixos-rebuild --target-host` deploys everything.
# No separate `nh home switch` needed.
{
  config,
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
    decky-loader = {
      enable = true;
      # Plugins (Junk-Store, Decky-Framegen, etc.) need these in PATH
      extraPackages = [
        pkgs.python3 # python3 for Junk-Store
        pkgs.p7zip # 7z for Decky-Framegen extraction
      ];
      # Decky Loader's run() defaults env to {"LD_LIBRARY_PATH": ""},
      # which replaces the entire environment including PATH.
      # This breaks systemctl calls. Fix: change default to None.
      # Pin v3.2.4 — fixes CEF rendering error (missing Field component in @decky/ui).
      package = pkgs.decky-loader.overridePythonAttrs (old: rec {
        version = "3.2.4";
        src = pkgs.fetchFromGitHub {
          owner = "SteamDeckHomebrew";
          repo = "decky-loader";
          rev = "v3.2.4";
          hash = "sha256-QC1vmosEY+gQGMskA+y3yz3zpHJjXNjoYk3TA93ffJw=";
        };
        pnpmDeps = old.pnpmDeps.override {
          inherit src version;
          hash = "sha256-rjou5KDHlF0MWAMzIKjc9UiIKk8t626SOM1Nw7WQzy4=";
        };
        postPatch = (old.postPatch or "") + ''
          find . -name localplatformlinux.py -exec sed -i 's@env: ENV | None = {"LD_LIBRARY_PATH": ""}@env: ENV | None = None@' {} +
        '';
      });
    };
  };

  # Decky Loader requires Steam CEF remote debugging to inject its UI.
  # Create the flag file before Steam starts (Jovian doesn't auto-enable for security).
  systemd.services.steam-cef-debug = {
    description = "Enable Steam CEF debugging for Decky Loader";
    serviceConfig = {
      Type = "oneshot";
      User = config.jovian.steam.user;
      ExecStart = "/bin/sh -c 'mkdir -p ~/.steam/steam && touch ~/.steam/steam/.cef-enable-remote-debugging'";
    };
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
  };

  # Decky LSFG-VK: fix default Lossless.dll path for NixOS (Steam library is under ~/.local, not /games)
  systemd.services.decky-loader.preStart = lib.mkAfter ''
    sed -i 's|dll = .*|dll = "/home/ammar/.local/share/Steam/steamapps/common/Lossless Scaling/Lossless.dll"|' \
      /var/lib/decky-loader/.config/lsfg-vk/conf.toml 2>/dev/null || true
  '';

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
