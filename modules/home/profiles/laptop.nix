{ config, pkgs, lib, ... }:

{
  # Common laptop configurations
  services.blueman-applet.enable = true;
  
  # Add other laptop-specific configurations here
  # For example:
  # - Power management settings
  # - Battery monitoring
  # - Screen brightness controls
}