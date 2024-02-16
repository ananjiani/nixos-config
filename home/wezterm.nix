{config, pkgs, lib, ...}:

{

  programs.wezterm.enable = true;
  programs.wezterm.extraConfig = ''
  -- Pull in the wezterm API
  local wezterm = require 'wezterm'

  -- This will hold the configuration.
  local config = wezterm.config_builder()

  -- This is where you actually apply your config choices

  -- For example, changing the color scheme:
  config.color_scheme = 'Gruvbox Material (Gogh)'
  config.default_prog = { '${pkgs.fish}/bin/fish' }
  config.font_size = 14.0
  -- and finally, return the configuration to wezterm
  return config

  '';
}
