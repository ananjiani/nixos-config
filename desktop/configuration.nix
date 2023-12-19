# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./samba.nix
    ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  
#   # Auto upgrade
#   system.autoUpgrade.enable = true;
#   system.autoUpgrade.allowReboot = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.kernelModules = ["amdgpu"];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  networking.hostName = "ammars-pc"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.hosts = {
    "192.168.1.85" = ["BRWC894023BADD0.local" "BRWC894023BADD0"];
  };
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  # Enable sound.
  sound.enable = true;
  security = {
    polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
            if ((action.id == "org.corectrl.helper.init" ||
                action.id == "org.corectrl.helperkiller.init") &&
                subject.local == true &&
                subject.active == true &&
                subject.isInGroup("users")) {
                    return polkit.Result.YES;
            }
        });
      '';
    };
    rtkit.enable = true;
  };

  services = {
    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      layout = "us";
      videoDrivers = ["amdgpu"];
      displayManager.sddm.sugarCandyNix = {
        enable = true;
        settings = {
          Background = lib.cleanSource ./wallpapers/revachol-horse.jpg;
          ScaleImageCropped = false;
          ScreenWidth = 5120;
          ScreenHeight = 1440;
          FormPosition = "center";
          FullBlur = true;
          ForceHideCompletePassword = true;
          HeaderText = "";
          DimBackgroundImage = 0.3;
        };
      };
    };
    # services.xserver.xkbOptions = "eurosign:e,caps:escape";

    # services.xserver.desktopManager.plasma5.enable = true;


    # Configure pipewire
    pipewire = {
      enable = true;
      wireplumber.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # jack.enable = true;
    };

    # Enable CUPS to print documents.
    printing.enable = true;
   
   avahi = {
      enable = true;
      nssmdns = true;
      openFirewall = true;
    };

    upower.enable = true;

    flatpak.enable = true;

    dbus.enable = true;

    gvfs.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };


  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  fonts.packages = with pkgs; [
    nerdfonts
    font-awesome
  ];

  programs = {
    hyprland.enable = true;
    steam = {
      enable = true;
    };
    thunar.enable = true;
    file-roller.enable = true;
    gamemode.enable = true;
    gamescope.capSysNice = true;
  };

  # Enable Settings for AMD
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  hardware = {
    opengl.enable = true;
    opengl.driSupport = true;
    opengl.driSupport32Bit = true;
    opengl.extraPackages = with pkgs; [
      rocm-opencl-icd
      rocm-opencl-runtime
      #amdvlk
      #driversi686Linux.amdvlk
    ];

  };

  # Allow specific unfree software
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg)[
      "steam"
      "steam-original"
      "steam-run"
      "code"
      "vscode"
  ];
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ammar = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      firefox
      tree
      vscode.fhs
      remmina
      openconnect
      signal-desktop
      lutris     
    ];
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    zip
    unzip
    lf
    pcmanfm
    mpd
    gedit
    pavucontrol
    light
    wlogout
    hyprpicker
    waybar
    libnotify
    mako
    copyq
    fuzzel
    alacritty
    killall
    swaybg
    neofetch
    image-roll
    corectrl
    polkit_gnome
    libreoffice
    grim
    slurp
    wl-clipboard
    swappy
    imagemagick
    steamtinkerlaunch
    vscodium-fhs
    gamescope_git
    nwg-displays
    wlr-randr
    wineWowPackages.staging
    
  ];

  chaotic = {
    steam.extraCompatPackages = with pkgs; [
      proton-ge-custom
    ];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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

