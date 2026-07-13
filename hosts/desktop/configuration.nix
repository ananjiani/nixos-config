# ammars-pc — Primary desktop workstation
{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../_profiles/workstation/configuration.nix
    ./samba.nix
    ../../modules/nixos/amd.nix
    ../../modules/nixos/bluetooth.nix
    ../../modules/nixos/android.nix
    ../../modules/nixos/nfs-client.nix
    ../../modules/nixos/openconnect.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/tailscale.nix
  ];

  # Desktop uses age key from home directory (servers use /var/lib/sops-nix/)
  sops.age.keyFile = "/home/ammar/.config/sops/age/keys.txt";

  # Custom modules configuration
  modules = {
    # Mount NFS share from theoden
    nfs-client.enable = true;

    # Tailscale client (not exit node - Mullvad handles regular traffic).
    #
    # tailscaled runs INSIDE the Mullvad tunnel (excludeFromMullvad = false).
    # Its DERP/WG traffic goes to erebor's public IP through Mullvad, which
    # works fine post-ADR-002 (Headscale on erebor, no NAT hairpin). Excluding
    # it caused four postmortems; see ADR-004. Reaching tailnet IPs from
    # unmarked local processes is handled by the mullvad-tailscale-bypass
    # service below (main-table CGNAT route + ct-mark fixup), not exclusion.
    tailscale = {
      enable = true;
      excludeFromMullvad = false;
      operator = "ammar";
    };

    # Mullvad custom DNS — LAN resolvers ONLY, never a public fallback.
    #
    # When Mullvad is handed a mix of LAN and public DNS servers, it filters
    # the LAN ones out before publishing to systemd-resolved on wg0-mullvad
    # (they aren't reachable via the WG tunnel) and keeps only the public one.
    # Combined with wg0-mullvad's `~.` catch-all routing domain, that sends
    # every DNS query to a public resolver, which bypasses AdGuard's
    # split-DNS rewrite for ts.dimensiondoor.xyz — breaking Tailscale login
    # because we'd then try to NAT-hairpin our own WAN IP (which OPNsense
    # can't do). See postmortem 2026-04-07 and the 2026-04-10 regression.
    #
    # Do NOT re-point this at `config.networking.nameservers` — the two
    # lists look alike but have opposite semantics (fault-tolerant fallback
    # vs. must-exclude-tunnel-reachable).
    privacy.mullvadCustomDns = [
      "192.168.1.53" # AdGuard HA VIP
      "192.168.1.1" # OPNsense router (AdGuard upstream)
    ];
  };

  networking = {
    hostName = "ammars-pc";

    # Wake-on-LAN via wakeOnLan.enable no-ops on this NIC driver (nixpkgs#415213:
    # `ethtool` stays `Wake-on: d` despite the option). Applied manually via the
    # systemd service + udev rule below instead. NIC keeps PHY powered in S3 so
    # `wakeonlan 30:c5:99:26:f4:c5` from another LAN host can resume the box.
    # Requires BIOS: WoL/PCI power-up = on, ErP = off, Deep Sx = off.
    # Verify post-reboot: `sudo ethtool eno1 | grep Wake-on` should show `g`.
    # Tailscale bypass is loaded via systemd (see systemd.services.mullvad-tailscale-bypass)
    # because networking.nftables.tables requires networking.nftables.enable which
    # switches the entire firewall backend and breaks iptables-nft rules (Docker, Tailscale).
  };
  # Reach Tailscale CGNAT peers (100.64.0.0/10) from unmarked local
  # processes while Mullvad is connected. See ADR-004.
  #
  # tailscaled is NOT excluded from Mullvad (modules.tailscale.excludeFromMullvad
  # = false) — its DERP/WG traffic rides the tunnel to erebor's public IP,
  # which works post-ADR-002 (Headscale on erebor, no NAT hairpin). But
  # Mullvad installs an unmarked-catch `ip rule` ("not fwmark <mole> lookup
  # <tunnel>") that pulls any unmarked packet — a shell curl or vault-agent
  # to 100.64.0.21 — into the tunnel, where CGNAT is unroutable → blackhole.
  #
  # Fix without racing Mullvad's rule priorities: Mullvad adds its rules with
  # NO fixed priority (talpid RuleHeader::default()), so the kernel keeps
  # renumbering them just below our lowest rule — a fixed-priority bypass can
  # never durably win (the 2026-07-11 incident). BUT Mullvad always also adds
  # a companion `lookup main suppress_prefixlength 0` rule that sits ABOVE its
  # tunnel-catch. A /10 route in the MAIN table is resolved by that suppress
  # rule (only default /0 routes are suppressed) before the tunnel-catch is
  # consulted. So route CGNAT via a main-table route (drift-immune) and set
  # ct mark 0xf41 (nft filter, not type route) so Mullvad's firewall accepts
  # the tailscale0-bound packet.
  #
  # Do NOT use networking.nftables.enable — switches firewall backend and
  # breaks iptables-nft (Docker, Tailscale).
  systemd = {
    # Wake from suspend for the 03:45 store optimise (idle-scheduled in
    # base.nix). swayidle's 30-min idle timeout should re-suspend afterwards;
    # if the machine stays awake overnight instead, add a guarded re-suspend.
    timers.nix-optimise.timerConfig.WakeSystem = true;

    services = {
      mullvad-tailscale-bypass = {
        description = "Reach Tailscale CGNAT peers through Mullvad";
        after = [
          "network.target"
          "mullvad-daemon.service"
          "tailscaled.service"
        ];
        wants = [
          "mullvad-daemon.service"
          "tailscaled.service"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "mullvad-tailscale-bypass-start" ''
            set -euo pipefail
            ip=${pkgs.iproute2}/bin/ip
            nft=${pkgs.nftables}/bin/nft

            # CGNAT + tailnet ULA via tailscale0 in MAIN table. Resolved by
            # Mullvad's own suppress rule, so immune to its priority drift.
            $ip    route replace 100.64.0.0/10 dev tailscale0
            $ip -6 route replace fd7a:115c:a1e0::/48 dev tailscale0

            # ct mark 0xf41 so Mullvad's firewall accepts the tailscale0 packet.
            $nft delete table inet mullvad-mark-fixup 2>/dev/null || true
            $nft -f - <<'NFT'
            table inet mullvad-mark-fixup {
              chain output {
                type filter hook output priority -10; policy accept;
                ip daddr 100.64.0.0/10 ct mark set 0x00000f41
                ip6 daddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41
              }
              chain input {
                type filter hook input priority -100; policy accept;
                ip saddr 100.64.0.0/10 ct mark set 0x00000f41
                ip6 saddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41
              }
            }
            NFT
          '';
          # Best-effort stop — missing route/table is fine.
          ExecStop = pkgs.writeShellScript "mullvad-tailscale-bypass-stop" ''
            ip=${pkgs.iproute2}/bin/ip
            nft=${pkgs.nftables}/bin/nft
            $ip    route del 100.64.0.0/10 dev tailscale0 2>/dev/null || true
            $ip -6 route del fd7a:115c:a1e0::/48 dev tailscale0 2>/dev/null || true
            $nft delete table inet mullvad-mark-fixup 2>/dev/null || true
            exit 0
          '';
        };
      };

      # Re-apply after mullvad-daemon restarts (it re-inits its rule set).
      mullvad-daemon.serviceConfig.ExecStartPost = [
        "+${pkgs.systemd}/bin/systemctl --no-block try-restart mullvad-tailscale-bypass.service"
      ];

      # Wake-on-LAN: re-apply magic-packet policy at boot and on every link add.
      # networking.interfaces.eno1.wakeOnLan.enable is a no-op on this driver (see comment above).
      wake-on-lan = {
        description = "Enable Wake-on-LAN (magic packet) on eno1";
        after = [ "network-pre.target" ];
        wants = [ "network-pre.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.ethtool}/bin/ethtool -s eno1 wol g";
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    signal-desktop
    cifs-utils
    brave # fallback during brave-origin transition
  ];

  virtualisation.docker.enable = true;

  services = {
    udev = {
      enable = true;
      extraRules = ''
        # Re-apply WoL on NIC (re)bind — driver resets the flag on link flap.
        ACTION=="add", SUBSYSTEM=="net", KERNEL=="eno1", RUN+="${pkgs.ethtool}/bin/ethtool -s eno1 wol g"
      '';
    };
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };
  };

  gaming.enable = true;

  moondeck = {
    enable = true;
    sunshine.enable = true;
  };

  desktop.niri.enable = true;

  opendeck.enable = true;

  programs = {
    # Experimental HDR fork — https://github.com/niri-wm/niri/discussions/1128
    niri.package = pkgs.niri-hdr;

    ssh.knownHosts = {
      "theoden.lan".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAzH8WouJOjPIrJH3ngAxWaSEw6YLDREAbFxIgr7mjX";
      "boromir.lan".publicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEsPlw7G8qNx5esED6AHc6EQhZk0nuLxfwh1IlZ1k5Nb";
    };

    # Brave browser - disable DoH since OPNsense handles DNS with Mullvad DoT
    brave = {
      enable = true;
      package = pkgs.brave-origin;
      features.sync = true;
      features.aiChat = true;
      doh.enable = false; # Use system DNS (router-level encryption)
      searchEngine = {
        enable = true;
        searchUrl = "https://searxng.lan/search?q={searchTerms}";
        suggestUrl = "https://searxng.lan/autocompleter?q={searchTerms}";
      };
    };
  };

}
