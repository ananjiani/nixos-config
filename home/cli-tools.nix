{ config, pkgs, lib, sops-nix, ... }:

{
  home.shellAliases = {
    df = "duf";
    du = "dust";
    grep = "rg";
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
   
    fzf = {
      enable = true;
      defaultCommand = "fd . $HOME -H";
      colors = {
        fg = "#ebdbb2";
        bg = "#282828";
        hl = "#fabd2f";
        "fg+" = "#ebdbb2";
        "bg+" = "#3c3836";
        "hl+" = "#fabd2f";
        info = "#83a598";
        prompt = "#bdae93";
        spinner = "#fabd2f";
        pointer = "#83a598";
        marker = "#fe8019";
        header = "#665c54";
      };
    };
   
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
