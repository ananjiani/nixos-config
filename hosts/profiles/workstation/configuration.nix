# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{
  ...
}:

{
  imports = [
    ../../../modules/nixos/wm.nix
    ../../../modules/nixos/utils.nix
    ../../../modules/nixos/fonts.nix
    ../../../modules/nixos/privacy.nix
  ];
  programs.nh = {
    enable = true;
    flake = "~/.dotfiles";
  };
}
