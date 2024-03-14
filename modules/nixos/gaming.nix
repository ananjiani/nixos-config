{ config, pkgs, lib, pkgs-stable, ... }:

{

  programs = {
    steam = {
      enable = true;
      package = pkgs.steam.override {
        extraEnv = {};
        extraLibraries = pkgs: with pkgs; [
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

  environment.systemPackages = 
    (with pkgs; [
      steamtinkerlaunch
      lutris
    ])

    ++

    (with pkgs-stable; [
      gamescope
    ]);

}
