{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [ microsoft-edge pgadmin4-desktopmode ];
}
