{ config, lib, pkgs, ... }:

{
  services.samba-wsdd.enable = true;
  networking.firewall.allowedTCPPorts = [
    5257
  ];
  networking.firewall.allowedUDPPorts = [
    3702
  ];
  
  services.samba = {
    enable = true;
    openFirewall = true;
    securityType = "user";
    shares = {
      bg3 = {
        path = "/mnt/nvme/SteamLibrary/steamapps/common/Baldurs Gate 3";
        browseable = "yes";
        "guest ok" = "yes";
        "read only" = "no";
      };
      bg3_local = {
        path = "/mnt/nvme/SteamLibrary/steamapps/compatdata/1086940/pfx/drive_c/users/steamuser/AppData/Local/Larian Studios/";
        browseable = "yes";
        "guest ok" = "yes";
        "read only" = "no";
      };
    };
  };
}