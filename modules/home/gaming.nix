{
  pkgs,
  ...
}:

{
  home.sessionVariables = {
    DXVK_HDR = "1";
  };

  home.packages = with pkgs; [
    # r2modman takes forever to build and i'm not using it anyway
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    wine-wayland
    protontricks
  ];

  programs = {
    mangohud = {
      enable = true;
      settings = {
        cpu_stats = true;
        cpu_temp = true;
        core_load = true;
        gpu_stats = true;
        gpu_temp = true;
        fps = true;
        frametime = true;
        frame_timing = true;
        hdr = true;
      };
    };
    vesktop = {
      enable = true;
      settings = {
        discordBranch = "stable";
        transparencyOption = "none";
        tray = true;
        autoStartMinimized = true;
        hardwareAcceleration = true;
        minimizeToTray = true;
      };
      vencord.settings = {
        useQuickCss = true;
        plugins = {
          ClearURLs.enable = true;
          SilentTyping.enable = true;
          VoiceChatDoubleClick.enable = true;
          WebKeybinds.enable = true;
          QuickReply.enable = true;
          NoTypingAnimation.enable = true;
          MessageLogger.enable = true;
          BetterFolders.enable = true;
        };
      };
    };
  };
}
