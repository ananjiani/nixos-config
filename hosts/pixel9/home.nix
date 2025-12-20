# Home Manager configuration for Pixel 9 (Debian AVF with Nix)
{
  ...
}:
{
  imports = [
    # Terminal tools
    ../../modules/home/terminal/core.nix
    ../../modules/home/terminal/monitoring.nix
    ../../modules/home/config/defaults.nix
  ];

  # Enable dendritic doom-emacs (terminal variant for AVF)
  doom-emacs = {
    enable = true;
    variant = "nox"; # Terminal-only for now; can use "pgtk" if VNC/Wayland forwarding is set up
    service.enable = true;
    autoSync = true;
  };

  # SSH client config
  programs.ssh = {
    enable = true;
    matchBlocks = {
      desktop = {
        hostname = ""; # Configure with your desktop's IP/hostname
        user = "ammar";
      };
    };
  };

  home = {
    username = "ammar";
    homeDirectory = "/home/ammar";
    stateVersion = "24.05";
  };

  programs.home-manager.enable = true;
}
