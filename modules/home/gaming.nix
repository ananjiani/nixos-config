{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    vesktop
    # r2modman takes forever to build and i'm not using it anyway
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    wine-wayland
    protontricks
  ];

  programs = {
    mangohud.enable = true;
  };
}
