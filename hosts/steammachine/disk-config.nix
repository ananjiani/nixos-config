{ lib, ... }:

{
  disko.devices = {
    disk.main = {
      # Prometheus: Kingston OM3SGP4512K2-A00 (476.9 GiB), the internal NVMe.
      # Confirmed on the machine via /dev/disk/by-id before install.
      device = lib.mkDefault "/dev/disk/by-id/nvme-KINGSTON_OM3SGP4512K2-A00_50026B7283C74E80";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
