{ config, lib, pkgs, ... }:

{
  services.samba-wsdd.enable = true;
  networking.firewall.allowedTCPPorts = [ 5257 ];
  networking.firewall.allowedUDPPorts = [ 3702 ];

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        security = "user";
      };
      home = {
        path = "/home/ammar";
        browseable = "yes";
        "guest ok" = "no";
        "read only" = "no";
      };
      nvme = {
        path = "/mnt/nvme";
        browseable = "yes";
        "guest ok" = "yes";
        "read only" = "no";
      };
    };
  };
}
