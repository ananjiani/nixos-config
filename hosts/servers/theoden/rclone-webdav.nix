# RetroArch Cloud Sync - WebDAV server via rclone
#
# RetroArch has built-in Cloud Sync (Settings → Saving → Cloud Sync) that syncs
# saves, save states, core configs, and shader presets across devices via
# WebDAV. This service is the WebDAV backend, fronted by k8s traefik at
# https://retroarch.lan (IngressRoute + manual Endpoints to 192.168.1.27:8086,
# cert from the lan-ca ClusterIssuer — same shape as romm.lan).
#
# rclone serves /var/lib/retroarch-sync over WebDAV on :8086 with HTTP basic
# auth. Password comes from vault (secret/nixos/retroarch-webdav). retroarch.cfg
# is excluded from sync by RetroArch itself, so no path/driver conflicts.
#
# Logs: journalctl -u rclone-webdav.service
{ pkgs, ... }:
let
  webdavEnv = ''
    {{ with secret "secret/data/nixos/retroarch-webdav" }}WEBDAV_PASS={{ index .Data.data "password" }}{{ end }}
  '';
in
{
  modules.vault-agent.secrets.retroarch-webdav-env = {
    path = "secret/nixos/retroarch-webdav";
    field = "password"; # ignored — template is set
    template = webdavEnv;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/retroarch-sync 0755 root root -"
  ];

  systemd.services.rclone-webdav = {
    description = "RetroArch Cloud Sync WebDAV server (rclone)";
    after = [
      "network-online.target"
      "vault-agent-default.service"
    ];
    wants = [
      "network-online.target"
      "vault-agent-default.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "retroarch-sync";
      EnvironmentFile = "/run/secrets/retroarch-webdav-env";
      ExecStart = "${pkgs.rclone}/bin/rclone serve webdav /var/lib/retroarch-sync --addr 0.0.0.0:8086 --user ammar --pass \"$WEBDAV_PASS\"";
      Restart = "on-failure";
      RestartSec = 5;

      # Hardening
      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 8086 ];
}
