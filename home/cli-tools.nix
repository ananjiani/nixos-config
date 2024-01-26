{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    chafa
    ripdrag
    atool
    ffmpeg
    gnupg
    jq
    poppler_utils
    ffmpegthumbnailer
  ];
}