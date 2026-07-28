# Denethor - Work VM (Proxmox VM on gondor, Work VLAN 30)
#
# Employer-approved workstation, deliberately isolated from the homelab:
# no Tailscale, no OpenBao/vault-agent, no SOPS secrets, no k3s/AdGuard,
# no LAN CA trust, no LAN Attic cache. It sits on VLAN 30 (10.30.30.0/24)
# and reaches the internet straight through WAN (not the router's Mullvad
# policy route) so Cisco AnyConnect and its SAML MFA flow see a normal
# residential IP.
#
# Only the base profile (SSH/nix/locale) and the NetworkManager OpenConnect
# module are shared with the rest of the fleet.
#
# WARNING: `nh home switch` is intentionally unsupported until a
# denethor-specific homeConfiguration exists. Do not add one casually —
# this host must stay free of homelab HM modules (secrets, LAN CA, etc.).
{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ../../_profiles/base.nix
    ../../../modules/nixos/openconnect.nix
  ];

  networking = {
    hostName = "denethor";
    enableIPv6 = false;

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

  # base modules.ssh opens SSH + mosh globally; pin SSH to ens18 only (above).
  services = {
    openssh.openFirewall = lib.mkForce false;

    qemuGuest.enable = true;

    # Stock minimal desktop: XFCE on LightDM. ammar has no password (SSH is
    # key-only), so both the console and the greeter log straight in.
    # Screensaver off: passwordless autologin cannot unlock a lock screen.
    xserver = {
      enable = true;
      desktopManager.xfce = {
        enable = true;
        enableScreensaver = false;
      };
      displayManager.lightdm.enable = true;
    };
    displayManager.autoLogin = {
      enable = true;
      user = "ammar";
    };
    getty.autologinUser = "ammar";
  };

  programs.mosh.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    microsoft-edge # corporate SSO / Azure DevOps web
    (azure-cli.withExtensions [ azure-cli.extensions.azure-devops ])
    # Upstream agent packages, OAuth login only — no homelab wrapper modules
    # (those reference /run/secrets and searxng.lan).
    claude-code
    llm-agents.pi
  ];

  system.stateVersion = "25.11";
}
