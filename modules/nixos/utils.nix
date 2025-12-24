# Workstation-specific utilities and configuration
# Imports base.nix for universal foundation

{
  pkgs,
  ...
}:

{
  imports = [ ./base.nix ];

  # Workstation networking (servers use systemd-networkd or DHCP)
  networking.networkmanager = {
    enable = true;
    dns = "systemd-resolved"; # Use systemd-resolved for split DNS
  };

  # Split DNS: route .lan queries to OPNsense, everything else through VPN
  services.resolved = {
    enable = true;
    domains = [ "~lan" ]; # Route .lan to fallback DNS
    fallbackDns = [ "192.168.1.1" ]; # OPNsense for .lan resolution
  };

  environment.systemPackages = with pkgs; [
    neofetch
  ];

  # Add claude-code cache (nix-community is in base.nix)
  nix.settings = {
    substituters = [
      "https://claude-code.cachix.org"
    ];
    trusted-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    ];
  };

  programs = {
    kdeconnect.enable = true;
    # Enable ydotool for input automation
    # ydotool = {
    #   enable = true;
    #   group = "ydotool";
    # };

    gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      enableSSHSupport = true;
    };
  };

  # Add workstation-specific groups
  users.users.ammar = {
    extraGroups = [
      "docker"
      # "ydotool"
    ];
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Open SSH port
  networking.firewall.allowedTCPPorts = [ 22 ];

  security = {
    polkit = {
      enable = true;
    };
    rtkit.enable = true;
  };

  services.pcscd.enable = true;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
