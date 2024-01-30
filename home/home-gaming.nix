{ config, pkgs, lib, ... }:

{
    home.packages = with pkgs; [
        webcord
        r2modman
    ];

    programs = {
        mangohud.enable = true;
    };
}
