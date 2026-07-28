# Portable Home Manager dev profile — coding agents + toolchain only.
# No secrets, LAN services, Tailscale, Collie, ntfy, mirror, or tea.
# Homelab-specific overlays (sops, tea, Herdr plugins) stay on the host.
# Defaults on for Aragorn/workstations. Isolated hosts (Denethor) set:
#   claudeCode.homelabBackends.enable = false
#   piCodingAgent.homelabProviders.enable = false  # empty models + safe settings
#   piCodingAgent.homelabExtensions.enable = false # drop secret-backed extensions
#   piCodingAgent.searxngUrl = null
#   devPrograms.npmGlobalPackages = null           # no install/uninstall
# When providers/extensions are off, Pi settings + extensions become immutable
# filtered store paths (/settings is repo-managed there). Remaining out-of-store
# Pi/Herdr symlinks still need a ~/.dotfiles checkout.
{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.stylix.homeModules.stylix
    ../../../modules/home/dev/pi-coding-agent.nix
    ../../../modules/home/dev/claude-code.nix
    ../../../modules/home/dev/nix-direnv.nix
    ../../../modules/home/dev/lang/python.nix
    ../../../modules/home/dev/lang/nixlang.nix
    ../../../modules/home/dev/nix-index.nix
    ../../../modules/home/dev/programs.nix
  ];

  # Pi (and friends) read config.lib.stylix.colors; headless hosts must not
  # activate Stylix's KDE/dconf targets.
  stylix = {
    enable = false;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-soft.yaml";
    polarity = "dark";
  };
}
