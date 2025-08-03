{
  lib,
  ...
}:

{
  imports = [
    ../default/home.nix
    ../../modules/home/gaming.nix
    ../../modules/home/config/wallpaper.nix
  ];

  wallpaper = {
    enable = true;
    path = ../default/wallpapers/revachol.jpg;
    mode = lib.mkForce "fit";
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "DP-2,5120x1440@240,0x1440,1,vrr,2"
      "DP-1,3840x2160@60,2560x0,1.5"
      "HDMI-A-1,2560x1440@60,0x0,1"
    ];
    workspace = [
      # Main monitor (DP-2) - workspaces 1-3 for focused work (always visible)
      "1, monitor:DP-2, default:true, layoutopt:orientation:center, persistent:true"
      "2, monitor:DP-2, layoutopt:orientation:center, persistent:true"
      "3, monitor:DP-2, layoutopt:orientation:center, persistent:true"

      # Left monitor (HDMI-A-1) - workspace 4 for communication (dwindle for multiple chats)
      "4, monitor:HDMI-A-1, default:true, persistent:true"

      # Right monitor (DP-1) - workspace 5 for media/reference
      "5, monitor:DP-1, default:true, persistent:true"
    ];
    exec-once = [
      "corectrl"
      "steam -silent -cef-disable-gpu"
    ];
  };
}
