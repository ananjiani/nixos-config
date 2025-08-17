{ pkgs, ... }:

{
  # Storage: MergerFS and SnapRAID
  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
    snapraid
  ];

  # SnapRAID configuration
  environment.etc."snapraid.conf".source = ./snapraid.conf;

  # SnapRAID systemd services and timers
  systemd = {
    services = {
      snapraid-sync = {
        description = "SnapRAID sync";
        wants = [ "snapraid-diff.service" ];
        after = [ "snapraid-diff.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.snapraid}/bin/snapraid sync";
          User = "root";
        };
      };

      snapraid-scrub = {
        description = "SnapRAID scrub";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.snapraid}/bin/snapraid scrub -p new -o 10";
          User = "root";
        };
      };

      snapraid-diff = {
        description = "SnapRAID diff check";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.snapraid}/bin/snapraid diff";
          User = "root";
        };
      };
    };

    timers = {
      snapraid-sync = {
        description = "Run snapraid sync daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };

      snapraid-scrub = {
        description = "Run snapraid scrub weekly";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "2h";
        };
      };
    };
  };
}
