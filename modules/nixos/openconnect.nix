{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [ openconnect ];

  networking.networkmanager.plugins = [ pkgs.networkmanager-openconnect ];

  programs.nm-applet.enable = true;
}
