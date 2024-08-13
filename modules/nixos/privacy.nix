{ config, lib, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [ tor-browser ];
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
    enableExcludeWrapper = true;
  };
}
