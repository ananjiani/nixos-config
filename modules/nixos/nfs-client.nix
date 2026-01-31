# NFS client - mounts NFS share from theoden
{ lib, config, ... }:

let
  cfg = config.modules.nfs-client;
  mountOptions = [
    "nfsvers=4.2"
    "acl"
  ];
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
      default = "/";
      description = "NFS export path on the server (/ for NFSv4 with fsid=0)";
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
    # NFS client support
    boot.supportedFilesystems = [ "nfs" ];

    # Storage group for NFS write access (matches GID on theoden)
    users.groups.storage = {
      gid = 1500;
    };

    # Add user to storage group if specified
    users.users = lib.mkIf (cfg.user != null) {
      ${cfg.user}.extraGroups = [ "storage" ];
    };

    # Use explicit systemd units instead of fileSystems to avoid
    # automount reload failures during activation (NixOS bug:
    # automount units don't support reload, causing deploy-rs rollbacks)
    systemd.mounts = [
      {
        what = "${cfg.server}:${cfg.export}";
        where = cfg.mountPoint;
        type = "nfs";
        options = lib.concatStringsSep "," (mountOptions ++ lib.optional (!cfg.automount) "_netdev");
        wantedBy = lib.mkIf (!cfg.automount) [ "multi-user.target" ];
      }
    ];

    systemd.automounts = lib.mkIf cfg.automount [
      {
        where = cfg.mountPoint;
        automountConfig = {
          TimeoutIdleSec = "600";
        };
        wantedBy = [ "multi-user.target" ];
      }
    ];
  };
}
