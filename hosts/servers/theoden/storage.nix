# Storage configuration for Theoden (migrated from Faramir)
#
# Uses physical disks passed through from Proxmox, pooled with mergerfs.
# Storage layout:
#   - /mnt/disk1, /mnt/disk2: Data drives
#   - /mnt/storage: MergerFS unified pool
#   - /srv/nfs: Bind mount for NFS export
#   - /srv/nfs/{zot,voicemails,persona-mcp,attic}: direct binds of the matching
#     /mnt/disk2 paths, bypassing mergerfs for shares whose data already lives
#     entirely on disk2. Client-visible paths are unchanged.
{ pkgs, ... }:

{
  # Shared storage group for NFS access
  users.groups.storage = {
    gid = 1500;
  };

  # Create NFS directories with proper group ownership
  # Mode 2775 = setgid + rwxrwxr-x (new files inherit group)
  systemd.tmpfiles.rules = [
    "d /mnt/storage 2775 root storage -"
    "d /mnt/storage/games 2775 root storage -"
    "d /mnt/storage/games/library 2775 root storage -"
    "d /mnt/storage/games/saves 2775 ammar storage -"
    "d /mnt/storage/immich 2775 root storage -"
  ];

  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
  ];

  # Tripwire fired on every `switch-to-configuration`: a NixOS deploy that
  # changes storage.nix restarts the fstab-generated mnt-storage.mount. If
  # bind-mounts (/srv/nfs, container binds) hold it busy, the old mergerfs
  # instance lingers as a stacked/dead-FUSE shadow and running containers
  # stay pinned to it -> ENOTCONN -> 502 (2026-07-07 incident). Romm's
  # PartOf=mnt-storage.mount mitigates by restarting it; this check warns if a
  # deploy still stacked the mount so a human can act before a stale-bind
  # surfaces days later. Silent on clean deploys (1 entry per target).
  # Only entries whose TARGET is exactly $m count: /srv/nfs now has legitimate
  # child mounts (the direct disk2 binds), which are not stacking.
  system.activationScripts.storageMountCheck = ''
    for m in /mnt/storage /srv/nfs; do
      n=$(${pkgs.util-linux}/bin/findmnt -R "$m" --output TARGET --noheadings 2>/dev/null | ${pkgs.gnugrep}/bin/grep -cx "$m")
      if [ "$n" -gt 1 ]; then
        echo "storageMountCheck: WARNING $m has $n stacked mounts (expected 1) — deploy restarted mnt-storage.mount while busy; restart containers binding /mnt/storage" >&2
        ${pkgs.curl}/bin/curl -fsS -o /dev/null \
          -H "Title: theoden: stacked mount on $m" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$m has $n stacked mergerfs mounts (expected 1) after a deploy. Restart containers binding /mnt/storage (romm). Postmortem: 2026-07-07-1238." \
          "https://ntfy-home.dimensiondoor.xyz/monitoring" || true
      fi
    done
  '';

  # Storage filesystem configuration
  fileSystems = {
    # Data drives for MergerFS pool
    "/mnt/disk1" = {
      device = "/dev/disk/by-uuid/dc5e54fd-6474-4b88-a757-c31f62c37138"; # 2TB Seagate
      fsType = "ext4";
      options = [
        "defaults"
        "nofail"
      ];
    };

    "/mnt/disk2" = {
      device = "/dev/disk/by-uuid/18cee265-e408-43bc-b6fe-c5edde8cb354"; # 8TB Seagate
      fsType = "ext4";
      options = [
        "defaults"
        "nofail"
      ];
    };

    # MergerFS unified storage pool.
    # disk3 (1TB WD) was removed from the pool: 90 pending / 77 uncorrectable
    # sectors, and it held nothing but lost+found.
    # A NixOS deploy that changes this entry restarts mnt-storage.mount -> new
    # FUSE instance; the old one lingers if bind-mounts hold it busy, and
    # containers bind-mounting /mnt/storage stay pinned to the dead instance
    # (ENOTCONN -> 502; 2026-07-07 postmortem). Any container binding this pool
    # MUST set on its unit:
    #   PartOf = [ "mnt-storage.mount" ]; After = [ "mnt-storage.mount" ];
    # so the restart propagates and it re-binds the fresh instance.
    # See hosts/servers/theoden/romm.nix for the pattern (quadlet unitConfig).
    "/mnt/storage" = {
      device = "/mnt/disk1:/mnt/disk2";
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=mfs" # Most free space for new files
        "kernel-permissions-check=false" # Required for NFS: git creates 0444 objects with O_RDWR
        "inodecalc=path-hash" # Stable inodes for NFS export
        "func.getattr=newest"
        "func.access=ff"
        "func.chmod=ff"
        "func.chown=ff"
        "func.getxattr=ff"
        "func.listxattr=ff"
        "func.mkdir=epmfs"
        "func.mknod=ff"
        "func.removexattr=ff"
        "func.rename=ff"
        "func.rmdir=ff"
        "func.setxattr=ff"
        "func.symlink=ff"
        "func.truncate=ff"
        "func.unlink=ff"
        "func.utimens=ff"
      ];
    };

    # Bind mount for NFS export (symlinks don't work with NFS exports)
    "/srv/nfs" = {
      device = "/mnt/storage";
      fsType = "none";
      options = [ "bind" ];
    };

    # Direct binds from disk2 for the shares that must survive a mergerfs
    # outage (dead FUSE instance -> ENOTCONN) and must not depend on pool
    # policy for placement. All four already have their real data on disk2,
    # so these shadow the identical mergerfs-backed paths under /srv/nfs.
    # Each is exported explicitly in configuration.nix (no crossmnt).
    "/srv/nfs/zot" = {
      device = "/mnt/disk2/zot";
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/srv/nfs" ];
    };

    "/srv/nfs/voicemails" = {
      device = "/mnt/disk2/voicemails";
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/srv/nfs" ];
    };

    "/srv/nfs/persona-mcp" = {
      device = "/mnt/disk2/persona-mcp";
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/srv/nfs" ];
    };

    "/srv/nfs/attic" = {
      device = "/mnt/disk2/attic";
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/srv/nfs" ];
    };
  };
}
