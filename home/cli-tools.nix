{ config, pkgs, lib, ... }:

{
  programs = {
    zoxide.enable = true;
  };
  home.packages = with pkgs; [
    chafa
    ripdrag
    atool
    ffmpeg
    gnupg
    jq
    poppler_utils
    ffmpegthumbnailer
    pandoc
  ];
}
