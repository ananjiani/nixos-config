{ config, pkgs, lib, sops-nix, ... }:

{
  home.shellAliases = {
    df = "duf";
    du = "dust";
  };
#  imports = [
#    sops-nix.homeManagerModules.sops
#  ];
#
#  sops = {
#    defaultSopsFile = ../secrets/secrets.yaml;
#    defaultSopsFormat = "yaml";
#    sops.age.keyFile = "~/.config/sops/age/keys.txt";
#  };

  programs = {
    
    thefuck.enable = true;
  
    zoxide = {
      enable = true;
      options = [
  	"--cmd cd" #doesn't work on nushell and posix shells
      ];
    };

    ripgrep.enable = true;
    
    atuin = {
      enable = true;
      settings = {
    	keymap_mode = "vim-normal";
      #	key_path = config.sops.secrets.atuin_key.path;
      };
    };
    
  };

#  sops.secrets.atuin_key = {
#    sopsFile = ../secrets.yaml;
#  };

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
    sops
    tealdeer
    du-dust
    duf
    ripgrep-all
    fd
    sshfs
  ];
}
