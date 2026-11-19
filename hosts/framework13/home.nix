{
  pkgs,
  ...
}:

{
  imports = [
    ../_profiles/workstation/home.nix
    ../../modules/home/profiles/laptop.nix
    ../../modules/home/config/sops.nix
    ../../modules/home/dev/tea.nix
    ../../modules/home/work.nix
    ../../modules/home/org-roam-sync.nix
  ];

  desktop.niri.enable = true;

  programs.ssh.matchBlocks = {
    # SSH alias — stopgap until /etc/hosts has theoden.lan
    "theoden.lan".hostname = "192.168.1.27";
    # Denethor's Work VLAN only admits aragorn and ammars-pc; hop via aragorn.
    denethor = {
      hostname = "denethor.lan";
      proxyJump = "aragorn";
    };
  };

  services = {
    blueman-applet.enable = true;
    mpris-proxy.enable = true;
    syncthing.settings = {
      devices.ammars-pc = (import ../../lib/syncthing-hosts.nix).ammars-pc // {
        addresses = [
          "tcp://100.64.0.4:22000"
          "dynamic"
        ];
      };
      folders.org-roam.devices = [ "ammars-pc" ];
    };
  };

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
