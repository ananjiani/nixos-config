{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [ teams teams-for-linux microsoft-edge ];
}
