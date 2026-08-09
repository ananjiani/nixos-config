# Denethor - Work VM (Proxmox VM on gondor, Work VLAN 30)
#
# Employer-approved workstation, deliberately isolated from the homelab:
# no Tailscale, no OpenBao/vault-agent, no SOPS secrets, no k3s/AdGuard,
# no LAN CA trust, no LAN Attic cache. One deliberate exception: HTTPS to
# SearXNG's k3s ingress VIP (OPNsense pass rule + pinned /32 below), kept
# off the work VPN's full-tunnel default route so nothing homelab-bound
# ever enters tun0. It sits on VLAN 30 (10.30.30.0/24)
# and reaches the internet straight through WAN (not the router's Mullvad
# policy route) so Cisco AnyConnect and its SAML MFA flow see a normal
# residential IP.
#
# Only the base profile (SSH/nix/locale), the NetworkManager OpenConnect
# module, and the portable HM profiles (essentials + dev) are shared.
# Homelab overlays (sops, tea, Collie/ntfy/mirror Herdr plugins, vault-agent)
# must never land here.
#
# WARNING: embedded portable Home Manager (essentials + dev) is supported.
# Standalone `nh home switch` / homeConfiguration remains unsupported — do
# not add one casually; this host must stay free of homelab HM modules
# (secrets, LAN CA, Tailscale, Collie, etc.).
{
  lib,
  pkgs,
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ../../_profiles/base.nix
    ../../../modules/nixos/openconnect.nix
    inputs.home-manager-unstable.nixosModules.home-manager
  ];

  networking = {
    hostName = "denethor";
    enableIPv6 = false;

    # searxng.lan resolves via AdGuard split-DNS on the LAN only; this host
    # uses Quad9/corporate DNS, so pin it statically — no .lan queries leave
    # the box, and no LAN resolver dependency comes back in.
    hosts."192.168.1.52" = [ "searxng.lan" ];

    # NetworkManager owns the NIC (it sets networking.useDHCP = false itself);
    # the Work VLAN lease comes from Kea on the OPNsense opt4 interface.
    # Force empty global nameservers so base LAN DNS can never leak in.
    # Quad9 lives only on the ens18 NM profile below (ignore-auto-dns).
    # AnyConnect/OpenConnect is a separate NM connection: corporate DNS it
    # pushes can win while the VPN is up. Kea still hands Quad9 to installer
    # and future Work clients via the work DHCP subnet.
    nameservers = lib.mkForce [ ];

    # SSH only on the physical Proxmox NIC — not on AnyConnect/tunnel ifaces.
    # base modules.ssh enables openssh + mosh with global firewall opens; close
    # those and open TCP 22 solely on ens18.
    firewall.interfaces.ens18.allowedTCPPorts = [ 22 ];

    networkmanager = {
      enable = true;
      # Prefer the declarative ens18 profile over NM's ad-hoc "Wired connection".
      # OpenConnect VPN profiles are separate connection types and still work.
      settings.main.no-auto-default = "*";

      # Keep SSH to LAN admin hosts working after AnyConnect installs corporate
      # RFC1918 routes that would otherwise blackhole 192.168.1.0/24. Only the
      # two admin hosts — not the whole LAN subnet.
      ensureProfiles.profiles = {
        ens18 = {
          connection = {
            id = "ens18";
            type = "ethernet";
            interface-name = "ens18";
            autoconnect = true;
          };
          ipv4 = {
            method = "auto";
            # NM keyfile: semicolon-separated DNS; ignore DHCP DNS (dead Unbound).
            dns = "9.9.9.9;149.112.112.112";
            ignore-auto-dns = "true";
            route1 = "192.168.1.28/32,10.30.30.1"; # aragorn
            route2 = "192.168.1.50/32,10.30.30.1"; # ammars-pc
            route3 = "192.168.1.52/32,10.30.30.1"; # searxng.lan (k3s ingress VIP)
          };
          ipv6.method = "disabled";
        };

        "Work VPN" = {
          connection = {
            id = "Work VPN";
            type = "vpn";
            autoconnect = false;
          };
          vpn = {
            gateway = "https://dscvpn1.dcccd.edu";
            protocol = "anyconnect";
            service-type = "org.freedesktop.NetworkManager.openconnect";
            user-name = "e8000808";
            useragent = "AnyConnect";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };

  # NM needs the user in networkmanager for GUI/VPN control; merge with base
  # wheel + dialout (list concat, does not replace).
  users.users.ammar.extraGroups = [ "networkmanager" ];

  # Public caches only: theoden.lan (LAN Attic) is unreachable from VLAN 30
  # and a dead substituter stalls every build.
  nix.settings.substituters = lib.mkForce [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://claude-code.cachix.org"
  ];

  # Do not trust the homelab LAN CA — this host must not accept homelab-issued
  # certificates for any name.
  security = {
    pki.certificateFiles = lib.mkForce [ ];
    sudo.wheelNeedsPassword = false;
  };

  # Proxmox VM: GRUB on the disko-managed BIOS boot partition + virtio drivers
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

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # base modules.ssh opens SSH + mosh globally; pin SSH to ens18 only (above).
  services = {
    openssh.openFirewall = lib.mkForce false;

    qemuGuest.enable = true;
    spice-vdagentd.enable = true;

    # Stock minimal desktop: XFCE on LightDM. ammar has no password (SSH is
    # key-only), so both the console and the greeter log straight in.
    # Screensaver off: passwordless autologin cannot unlock a lock screen.
    xserver = {
      enable = true;
      desktopManager.xfce = {
        enable = true;
        enableScreensaver = false;
      };
      displayManager = {
        lightdm.enable = true;
        setupCommands = ''
          ${lib.getExe pkgs.xrandr} --output Virtual-1 --mode 1920x1080 --rate 60
        '';
      };
    };
    displayManager.autoLogin = {
      enable = true;
      user = "ammar";
    };
    getty.autologinUser = "ammar";

    # a11y bus for Pi computer-use / Cua Driver UI automation.
    gnome.at-spi2-core.enable = true;
  };

  programs.mosh.enable = lib.mkForce false;

  # AD DFS referrals need kernel DNS upcalls to resolve their target servers.
  environment = {
    etc."request-key.conf".text = ''
      create dns_resolver * * ${pkgs.keyutils}/bin/key.dns_resolver %k
    '';
    systemPackages = with pkgs; [
      cifs-utils
      keyutils
      microsoft-edge # corporate SSO / Azure DevOps web
      (azure-cli.withExtensions [ azure-cli.extensions.azure-devops ])
    ];
  };

  # Portable embedded HM only — essentials + dev. No server profile, no sops,
  # no tea, no homelab Herdr plugins. Homelab Claude backends + Pi secret
  # providers/extensions + searxng.lan + npm management are all off. Pi
  # settings/extensions become immutable filtered store paths here; other
  # Pi/Herdr paths still need a ~/.dotfiles checkout (encrypted secret files
  # may be present but are not decrypted here).
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar =
      { lib, ... }:
      {
        imports = [
          ../../_profiles/essentials/home.nix
          ../../_profiles/dev/home.nix
        ];
        piCodingAgent = {
          # web-search uses searxng.lan via the pinned /32 + firewall pinhole
          # (module default URL). Tavily stays off: no vault-agent here.
          tavilyKeyFile = null;
          homelabProviders.enable = false; # empty providers + filtered model list
          homelabExtensions.enable = false; # drop nvidia-nim + usage-tracker
          edgeDevtoolsUrl = "http://127.0.0.1:9222";
          computerUse = {
            enable = true; # Cua Driver desktop control (host-only)
            blockForegroundInput = true; # no global/foreground input steal
            displayFallback = ":0"; # LightDM X11 session when DISPLAY unset
          };
        };
        claudeCode.homelabBackends.enable = false;
        # null = no install and no uninstall (do not use [] — that cleans up)
        devPrograms.npmGlobalPackages = null;
        programs = {
          git.settings = {
            credential.helper = lib.mkForce "cache --timeout=3600";
            user.email = lib.mkForce "ananjiani@dallascollege.edu";
          };
          jujutsu.settings.user.email = lib.mkForce "ananjiani@dallascollege.edu";
        };

        # Edge with CDP on 127.0.0.1:9222 for Pi edge-devtools MCP. Separate
        # profile from personal Edge; loopback-only (CDP = full browser control).
        systemd.user.services.edge-agent = {
          Unit = {
            Description = "Microsoft Edge with remote debugging for Pi MCP";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.microsoft-edge}/bin/microsoft-edge --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 --user-data-dir=%h/.local/share/edge-agent --no-first-run --no-default-browser-check";
            Environment = [
              "DISPLAY=:0"
              "XAUTHORITY=%h/.Xauthority"
            ];
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
  };

  system.stateVersion = "25.11";
}
