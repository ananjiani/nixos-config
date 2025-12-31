# Storage configuration for Theoden (migrated from Faramir)
#
# Uses 3 physical disks passed through from Proxmox, pooled with mergerfs.
# Storage layout:
#   - /mnt/disk1, /mnt/disk2, /mnt/disk3: Data drives
#   - /mnt/storage: MergerFS unified pool (~11TB total)
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
  ];

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
        "func.getattr=newest"
        "func.access=ff"
        "func.chmod=ff"
        "func.chown=ff"
        "func.getxattr=ff"
        "func.listxattr=ff"
        "func.mkdir=ff"
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
