{
  pkgs,
  ...
}:

{
  programs = {
    steam = {
      enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      package = pkgs.steam.override {
        extraEnv = { };
        extraLibraries =
          pkgs: with pkgs; [
            xorg.libXcursor
            xorg.libXi
            xorg.libXinerama
            xorg.libXScrnSaver
            libpng
            libpulseaudio
            libvorbis
            stdenv.cc.cc.lib
            libkrb5
            keyutils
          ];
      };
    };
    gamemode.enable = true;
    gamemode.enableRenice = true;
  };

  programs.gamescope.enable = true;
  programs.gamescope.capSysNice = true;

  environment.systemPackages = with pkgs; [
    steamtinkerlaunch
    yad
    gamescope-wsi
    #lutris
  ];
}
