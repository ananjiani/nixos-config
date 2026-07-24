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
      # Run plugins as 'ammar' so $HOME matches the Steam library path.
      # Fixes LSFG-VK DLL detection and any other plugin that looks for
      # Steam files via HOME-relative paths.
      user = "ammar";
      # Plugins (Junk-Store, Decky-Framegen, etc.) need these in PATH
      extraPackages = [
        pkgs.python3 # python3 for Junk-Store
        pkgs.p7zip # 7z for Decky-Framegen extraction
      ];
      # Decky Loader's run() defaults env to {"LD_LIBRARY_PATH": ""},
      # which replaces the entire environment including PATH.
      # This breaks systemctl calls. Fix: change default to None.
      # Pin v3.2.6 — fixes React error #130 with June 2026 Steam UI builds.
      package = pkgs.decky-loader.overridePythonAttrs (old: rec {
        version = "3.2.6";
        src = pkgs.fetchFromGitHub {
          owner = "SteamDeckHomebrew";
          repo = "decky-loader";
          rev = "v3.2.6";
          hash = "sha256-p1bkLsZedTZ29POqdaXvVpPXzg9kBTKgUxkkEAyAkT0=";
        };
        # v3.2.6 ships frontend/pnpm-workspace.yaml with only the pnpm 10
        # `minimumReleaseAgeExclude` field; pnpm 9 requires `packages` and may
        # reject unknown fields, so replace it with a minimal single-package
        # workspace in both the deps fetcher and the frontend build.
        pnpmDeps = old.pnpmDeps.override {
          inherit src version;
          hash = "sha256-WgKycKbaZv9lovoo0IaCuV41qS4zUqm4vZxsMQBUdNk=";
          postPatch = ''
            printf 'packages:\n  - "."\n' > pnpm-workspace.yaml
          '';
        };
        postPatch = (old.postPatch or "") + ''
          find . -name localplatformlinux.py -exec sed -i 's@env: ENV | None = {"LD_LIBRARY_PATH": ""}@env: ENV | None = None@' {} +
          printf 'packages:\n  - "."\n' > frontend/pnpm-workspace.yaml
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

  # ── Gaming clients and Vulkan layers ───────────────────────────────
  environment.systemPackages = with pkgs; [
    # Stable path for MoonDeck's custom executable setting:
    # /run/current-system/sw/bin/moonlight
    moonlight-qt

    # The Decky LSFG-VK plugin handles config + launch script. Use the
    # nixpkgs-built layer so library paths resolve correctly on NixOS.
    lsfg-vk
  ];

  # Ensure the layer JSON is discoverable inside Proton (Steam Runtime).
  # /etc/vulkan/implicit_layer.d is always checked regardless of XDG vars.
  environment.etc."vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json".source =
    "${pkgs.lsfg-vk}/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json";

  # Replace plugin-installed layer files with symlinks to the nixpkgs-built
  # lsfg-vk.  The nixpkgs binary is compiled for NixOS with correct RUNPATH,
  # unlike the plugin's prebuilt.  Symlinks keep the plugin's install check
  # happy (it expects ~/.local/{lib,share/vulkan/implicit_layer.d}/).
  systemd.services.decky-loader.preStart = lib.mkAfter ''
    mkdir -p /home/ammar/.local/lib
    mkdir -p /home/ammar/.local/share/vulkan/implicit_layer.d
    ln -sf ${pkgs.lsfg-vk}/lib/liblsfg-vk.so /home/ammar/.local/lib/liblsfg-vk.so
    ln -sf ${pkgs.lsfg-vk}/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json /home/ammar/.local/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json

    # Buddy 1.9.2 reports Unknown because current Steam logs no longer contain
    # its SP Desktop_/SP BPM_ markers. Keep MoonDeck's user check, but do not
    # block the game launch on that unavailable UI-mode signal.
    runner=/var/lib/decky-loader/plugins/moondeck/python/lib/runner/moondeckapprunner.py
    if grep -q 'if mode == desired_mode:' "$runner" 2>/dev/null; then
      ${pkgs.gnused}/bin/sed -i \
        's/if mode == desired_mode:/if mode in (desired_mode, SteamUiMode.Unknown):/' \
        "$runner"
    fi
    if ! grep -q 'MoonDeckAppRunner.wait_for_stream_to_stop' "$runner" 2>/dev/null; then
      ${pkgs.gnused}/bin/sed -i \
        '0,/                        await client.end_stream()/s//                        await client.end_stream()\n                        await MoonDeckAppRunner.wait_for_stream_to_stop(client=client,\n                                                                          timeout=stream_rdy_timeout)/' \
        "$runner"
    fi

    moonlight_proxy=/var/lib/decky-loader/plugins/moondeck/python/lib/moonlightproxy.py
    if ! grep -q -- '--touchscreen-trackpad' "$moonlight_proxy" 2>/dev/null; then
      ${pkgs.gnused}/bin/sed -i \
        '/args += \["stream", hostname, host_app\]/i\        args += ["--touchscreen-trackpad"]' \
        "$moonlight_proxy"
    fi
  '';

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
  sops = {
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    secrets.tailscale_authkey = { };
  };

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
