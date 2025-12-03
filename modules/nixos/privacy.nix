{
  pkgs,
  ...
}:

{

  environment.systemPackages = with pkgs; [
    tor-browser
    mullvad-browser
    nitrokey-app2
    bitwarden-desktop
    bitwarden-cli
  ];
  services = {
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
      enableExcludeWrapper = true;
    };
  };

  hardware.nitrokey.enable = true;
}
