{config, pkgs, lib, ...}:
{
  services.xserver.windowManager.exwm = {
    enable = true;
    loadScript =  builtins.readFile ../home/emacs/doom-emacs/exwm.el;
  };

}
