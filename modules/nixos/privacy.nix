{
  pkgs,
  ...
}:

{

  environment.systemPackages = with pkgs; [
    tor-browser
    nitrokey-app2
    bitwarden
    bitwarden-cli
  ];
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
    enableExcludeWrapper = true;
  };

  hardware.nitrokey.enable = true;
}
