{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [ claude-code aider-chat gh pgadmin4-desktopmode ];
}
