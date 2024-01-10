{ config, pkgs, lib, ... }:

{

  programs = {
    steam.enable = true;
    gamemode.enable = true;
    gamescope.capSysNice = true;
  };

  environment.systemPackages = with pkgs; [
    gamescope
    steamtinkerlaunch
    wineWowPackages.staging
    lutris
    protontricks
  ];

}