{ config, pkgs, lib, ... }:

{
    home.packages = with pkgs; [
        webcord
    ];

    programs = {
        mangohud.enable = true;
    };
}