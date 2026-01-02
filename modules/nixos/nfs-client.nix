# NFS client - mounts NFS share from theoden
{ lib, config, ... }:

let
  cfg = config.modules.nfs-client;
in
{
  options.modules.nfs-client = {
    enable = lib.mkEnableOption "NFS client mount from theoden";

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nfs";
      description = "Where to mount the NFS share";
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.27";
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

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "ammar";
      description = "User to add to the storage group for NFS write access";
    };
  };

  config = lib.mkIf cfg.enable {
    # Storage group for NFS write access (matches GID on theoden)
    users.groups.storage = {
      gid = 1500;
    };

    # Add user to storage group if specified
    users.users = lib.mkIf (cfg.user != null) {
      ${cfg.user}.extraGroups = [ "storage" ];
    };
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
