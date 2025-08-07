{
  lib,
  ...
}:

{

  imports = [
    ../profiles/workstation/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/wallpaper.nix
  ];

  wallpaper = {
    enable = true;
    mode = lib.mkForce "fit";
  };

  services.mpris-proxy.enable = true;

  wayland.windowManager.hyprland.settings = {
    monitor = [ ",highrr,auto,1" ];
    # Wallpaper is now handled by the wallpaper module
  };

}
