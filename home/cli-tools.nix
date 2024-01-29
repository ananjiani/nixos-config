{ config, pkgs, lib, ... }:

{
  programs = {
    zoxide = {
      enable = true;
      options = [
	"--cmd cd" #doesn't work on nushell and posix shells
      ];
    };
    
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
