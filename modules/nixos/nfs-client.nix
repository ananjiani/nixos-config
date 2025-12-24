# NFS client - mounts faramir NFS share
{ lib, config, ... }:

let
  cfg = config.modules.nfs-client;
in
{
  options.modules.nfs-client = {
    enable = lib.mkEnableOption "NFS client mount from faramir";

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nfs";
      description = "Where to mount the NFS share";
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "faramir.lan";
      description = "NFS server hostname or IP";
    };

    export = lib.mkOption {
      type = lib.types.str;
      default = "/srv/nfs";
      description = "NFS export path on the server";
    };

    automount = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use automount (mount on first access, unmount after idle)";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${cfg.mountPoint} = {
      device = "${cfg.server}:${cfg.export}";
      fsType = "nfs";
      options =
        if cfg.automount then
          [
            "x-systemd.automount"
            "noauto"
            "x-systemd.idle-timeout=600"
          ]
        else
          [
            "_netdev"
          ];
    };
  };
}
