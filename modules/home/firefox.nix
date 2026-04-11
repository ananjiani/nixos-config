{
  pkgs,
  ...
}:

{
  programs.firefox = {
    enable = true;
  };

  stylix.targets.firefox.profileNames = [ "default" ];

  home.packages = with pkgs; [
    tridactyl-native
  ];

}
