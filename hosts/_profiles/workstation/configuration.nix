# Workstation profile — shared by desktop and laptop hosts
# Imports base.nix for universal foundation, adds workstation-specific config
{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../base.nix
    ../secrets.nix
    ../../../modules/nixos/fonts.nix
    ../../../modules/nixos/privacy.nix
  ];

  # Desktop compositor via dendritic module
  desktop.hyprland.enable = lib.mkDefault true;

  # Bifrost default VK for `claude-kimi` fish wrapper. vault-agent reads
  # directly from the k8s-canonical path (single source of truth).
  # Requires the vault-agent policy to allow read on secret/data/k8s/bifrost
  # (see terraform/openbao.tf vault_policy.vault_agent).
  modules.vault-agent.secrets.bifrost_api_key = {
    path = "secret/k8s/bifrost";
    field = "default-virtual-key";
    owner = "ammar";
    mode = "0400";
  };

  programs = {
    nh = {
      enable = true;
      flake = "~/.dotfiles";
    };
    kdeconnect.enable = true;
    gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      enableSSHSupport = true;
    };
  };

  # Workstation networking (servers use systemd-networkd or DHCP)
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved"; # Use systemd-resolved for split DNS
    };
    firewall.allowedTCPPorts = [ 22 ]; # SSH
  };

  # Split DNS: route .lan queries to OPNsense, everything else through VPN
  services = {
    resolved = {
      enable = true;
      domains = [ "~lan" ]; # Route .lan to fallback DNS
      fallbackDns = [ "192.168.1.1" ]; # OPNsense for .lan resolution
    };
    pcscd.enable = true;
  };

  environment.systemPackages = with pkgs; [
    fastfetch
  ];

  # Add workstation-specific groups
  users.users.ammar.extraGroups = [
    "docker"
  ];

  # EFI boot loader (all workstations use systemd-boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security = {
    polkit.enable = true;
    rtkit.enable = true;
  };

  system.stateVersion = "23.05";
}
