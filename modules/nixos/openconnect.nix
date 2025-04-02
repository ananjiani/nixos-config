{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ openconnect_gnutls ];
  networking.openconnect.package = pkgs.openconnect_gnutls;
  networking.openconnect.interfaces = {
    work-vpn = {
      gateway = "https://dscvpn1.dcccd.edu";
      user = "e8000808";
      protocol = "anyconnect";
      extraOptions = {
        servercert = "pin-sha256:mEOOUvE2PUqfn6cu66uQ2e3MieuembXDskTrzfmTgsY=";
      };
    };
  };
}
