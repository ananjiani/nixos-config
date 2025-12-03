{
  lib,
  ...
}:

{
  imports = [
    ../profiles/workstation/home.nix
    ../../modules/home/gaming.nix
    # crypto.nix is now imported via dendritic pattern in flake.nix
    ../../modules/home/config/wallpaper.nix
    ../../modules/home/config/sops.nix
  ];

  wallpaper = {
    enable = true;
    mode = lib.mkForce "fit";
  };

  crypto = {
    enable = true;
    cakewallet.enable = true;
  };

  moondeck = {
    enable = true;
    autostart = true; # headless mode via systemd
  };

  # email = {
  #   enable = true;
  #   thunderbird = {
  #     enable = true;

  #     # Enable ALL hardened settings from thunderbird-user.js
  #     useHardenedUserJs = true;

  #     # Auto-start and minimize to tray (handled by birdtray)
  #     autostart = true;

  #     # Enable Birdtray for system tray integration on Linux
  #     birdtray.enable = true;

  #     userPrefs = {
  #       # ProtonMail Bridge certificate was accepted during setup
  #       # Can now use strict pinning (2) for better security
  #       # Note: If you have issues, temporarily set to 1
  #       "security.cert_pinning.enforcement_level" = 2;
  #     };
  #   };
  #   protonBridge = {
  #     enable = true;
  #     autostart = true;
  #   };
  #   accounts = {
  #     proton = {
  #       address = "ammar.nanjiani@pm.me";
  #       realName = "Ammar Nanjiani";
  #       primary = true;
  #       imap = {
  #         host = "127.0.0.1";
  #         port = 1143;
  #       };
  #       smtp = {
  #         host = "127.0.0.1";
  #         port = 1025;
  #       };
  #       thunderbirdProfiles = [ "default" ];
  #       # Password from SOPS - the ProtonMail Bridge generated password
  #       passwordFile = config.sops.secrets.proton_bridge_password.path;
  #     };
  #   };
  # };

  wayland.windowManager.hyprland.settings = {
    # experimental = {
    #   xx_color_management_v4 = true;
    # };
    monitor = [
      "DP-2,5120x1440@240,0x1440,1,vrr,2" # bitdepth,10,cm,hdr,sdrbrightness,1.2,sdrsaturation,1.1
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
