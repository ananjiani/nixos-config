# Storage configuration for Theoden (migrated from Faramir)
#
# Uses 3 physical disks passed through from Proxmox, pooled with mergerfs.
# Storage layout:
#   - /mnt/disk1, /mnt/disk2, /mnt/disk3: Data drives
#   - /mnt/storage: MergerFS unified pool (~11TB total)
#   - /srv/nfs: Bind mount for NFS export
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
  # surfaces days later. Silent on clean deploys (findmnt -R == 1 entry).
  system.activationScripts.storageMountCheck = ''
    for m in /mnt/storage /srv/nfs; do
      n=$(${pkgs.util-linux}/bin/findmnt -R "$m" --output TARGET --noheadings 2>/dev/null | wc -l)
      if [ "$n" -gt 1 ]; then
        echo "storageMountCheck: WARNING $m has $n stacked mounts (expected 1) — deploy restarted mnt-storage.mount while busy; restart containers binding /mnt/storage" >&2
        ${pkgs.curl}/bin/curl -fsS -o /dev/null \
          -H "Title: theoden: stacked mount on $m" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$m has $n stacked mergerfs mounts (expected 1) after a deploy. Restart containers binding /mnt/storage (romm). Postmortem: 2026-07-07-1238." \
          "https://ntfy.dimensiondoor.xyz/monitoring" || true
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

    "/mnt/disk3" = {
      device = "/dev/disk/by-uuid/15bc428e-291e-4380-a234-a2df4b4b0297"; # 1TB WD
      fsType = "ext4";
      options = [
        "defaults"
        "nofail"
      ];
    };

    # MergerFS unified storage pool
    "/mnt/storage" = {
      device = "/mnt/disk1:/mnt/disk2:/mnt/disk3";
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
  };
}
