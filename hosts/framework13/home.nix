{
  pkgs,
  ...
}:

{
  imports = [
    ../_profiles/workstation/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/sops.nix
    ../../modules/home/work.nix
  ];

  desktop.niri.enable = true;

  # SSH alias — stopgap until /etc/hosts has theoden.lan
  programs.ssh.matchBlocks."theoden.lan" = {
    hostname = "192.168.1.27";
  };

  services.blueman-applet.enable = true;
  services.mpris-proxy.enable = true;

  home.packages = with pkgs; [
    signal-desktop
    moonlight-qt
  ];
  wayland.windowManager.hyprland.settings = {
    monitor = [
      "eDP-1,2256x1504@60,0x0,1.175"
      ",preferred,auto,1"
    ];
    # Wallpaper is now handled by the wallpaper module
  };

  # niri output layout matching the hyprland monitor block above
  programs.niri.settings.outputs."eDP-1" = {
    mode = {
      width = 2256;
      height = 1504;
      refresh = 60.0;
    };
    position = {
      x = 0;
      y = 0;
    };
    scale = 1.175;
  };
}
