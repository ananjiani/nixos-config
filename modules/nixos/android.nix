{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    android-tools
  ];
  users.users.ammar.extraGroups = [ "adbusers" ];
}
