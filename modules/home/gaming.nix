{
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    vesktop
    r2modman
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    wine-wayland
    protontricks
  ];

  programs = {
    mangohud.enable = true;
  };
}
