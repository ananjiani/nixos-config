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

    # Tailscale client (not exit node - Mullvad handles regular traffic)
    tailscale = {
      enable = true;
      excludeFromMullvad = true;
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
  # Mullvad ↔ Tailscale coexistence on this host.
  #
  # Background (2026-07-11):
  # Mullvad installs `ip rule 5209: not fwmark 0x6d6f6c65 lookup <tunnel>`.
  # That sends ALL non-mole-mark traffic into the tunnel — including
  # tailscaled's own DERP/WG packets (SO_MARK 0x80000) and packets to
  # 100.64.0.0/10. Mullvad's built-in split-tunnel mangle uses
  # `type route` + `meta cgroup` to set mole mark and re-fib; on kernel
  # 6.18 that re-fib is a no-op (nft counters fire, src stays tunnel IP,
  # then `oif wg0 ct mark 0xf41 drop` blackholes the packet).
  #
  # Working approach — don't re-fib, fix the policy rules instead:
  #   1. ip rules ahead of 5209 so tailscale's SO_MARK 0x80000 and mole
  #      mark 0x6d6f6c65 use main/table 52 (never the tunnel table).
  #   2. ip rule for daddr 100.64.0.0/10 → table 52 so unmarked local
  #      processes (curl, bao, deploy) reach peers without SO_MARK.
  #   3. nft *filter* (not type route) sets ct mark 0xf41 so Mullvad's
  #      firewall accepts the now-correctly-routed packets.
  #
  # Do NOT use networking.nftables.enable — switches firewall backend
  # and breaks iptables-nft (Docker, Tailscale).
  systemd = {
    # Wake from suspend for the 03:45 store optimise (idle-scheduled in
    # base.nix). swayidle's 30-min idle timeout should re-suspend afterwards;
    # if the machine stays awake overnight instead, add a guarded re-suspend.
    timers.nix-optimise.timerConfig.WakeSystem = true;

    services = {
      mullvad-tailscale-bypass = {
        description = "Policy-routing bypass for Tailscale through Mullvad";
        after = [
          "network.target"
          "mullvad-daemon.service"
        ];
        wants = [ "mullvad-daemon.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "mullvad-tailscale-bypass-start" ''
            set -euo pipefail
            ip=${pkgs.iproute2}/bin/ip
            nft=${pkgs.nftables}/bin/nft

            # Drop prior copies (v4 + v6 — `ip rule del` is family-specific).
            for p in 5180 5181 5190 5191 5192 5200 5201 5202; do
              while $ip rule del priority "$p" 2>/dev/null; do :; done
              while $ip -6 rule del priority "$p" 2>/dev/null; do :; done
            done

            # Unmarked → Tailscale CGNAT peers (curl/bao/deploy from shell).
            $ip rule add priority 5180 to 100.64.0.0/10 lookup 52
            $ip -6 rule add priority 5181 to fd7a:115c:a1e0::/48 lookup 52

            # Mole mark (mullvad-exclude / docs mark 0x6d6f6c65).
            $ip rule add priority 5190 fwmark 0x6d6f6c65 lookup main suppress_prefixlength 0
            $ip rule add priority 5191 fwmark 0x6d6f6c65 lookup 52
            $ip rule add priority 5192 fwmark 0x6d6f6c65 lookup main

            # Tailscale's own SO_MARK 0x80000 (DERP, control, peer WG).
            $ip rule add priority 5200 fwmark 0x80000/0xff0000 lookup main suppress_prefixlength 0
            $ip rule add priority 5201 fwmark 0x80000/0xff0000 lookup 52
            $ip rule add priority 5202 fwmark 0x80000/0xff0000 lookup main

            # ct mark fixup — filter only, no re-fib.
            $nft delete table inet mullvad-mark-fixup 2>/dev/null || true
            $nft delete table inet mullvad-tailscale-bypass 2>/dev/null || true
            $nft -f - <<'NFT'
            table inet mullvad-mark-fixup {
              chain output {
                type filter hook output priority -10; policy accept;
                meta mark and 0xff0000 == 0x80000 ct mark set 0x00000f41
                meta mark 0x6d6f6c65 ct mark set 0x00000f41
                ip daddr 100.64.0.0/10 ct mark set 0x00000f41
                ip6 daddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41
              }
              chain prerouting {
                type filter hook prerouting priority -150; policy accept;
                ct mark 0x00000f41 meta mark set 0x6d6f6c65
              }
              chain input {
                type filter hook input priority -100; policy accept;
                ip saddr 100.64.0.0/10 ct mark set 0x00000f41
                ip6 saddr fd7a:115c:a1e0::/48 ct mark set 0x00000f41
              }
            }
            NFT
          '';
          # Never fail stop — missing rules/tables are fine (old unit, partial apply).
          ExecStop = pkgs.writeShellScript "mullvad-tailscale-bypass-stop" ''
            ip=${pkgs.iproute2}/bin/ip
            nft=${pkgs.nftables}/bin/nft
            for p in 5180 5181 5190 5191 5192 5200 5201 5202; do
              while $ip rule del priority "$p" 2>/dev/null; do :; done
              while $ip -6 rule del priority "$p" 2>/dev/null; do :; done
            done
            $nft delete table inet mullvad-mark-fixup 2>/dev/null || true
            $nft delete table inet mullvad-tailscale-bypass 2>/dev/null || true
            exit 0
          '';
        };
      };

      # Re-apply after mullvad-daemon restarts (reinstalls rule 5209).
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
