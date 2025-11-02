{
  pkgs,
  lib,
  ...
}:

{
  programs = {
    steam = {
      enable = true;
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
    #lutris
  ];
}
