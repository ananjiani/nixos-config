{
  lib,
  ...
}:

{

  imports = [
    ../default/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/wallpaper.nix
  ];

  wallpaper = {
    enable = true;
    path = ../default/wallpapers/revachol.jpg;
    mode = lib.mkForce "fit";
  };

  services.mpris-proxy.enable = true;

  wayland.windowManager.hyprland.settings = {
    monitor = [ ",highrr,auto,1" ];
    # Wallpaper is now handled by the wallpaper module
  };

}
