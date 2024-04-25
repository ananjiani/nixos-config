{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [ teams-for-linux microsoft-edge ];
}
