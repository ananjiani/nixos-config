{ config, pkgs, lib, ... }:

{

  boot.initrd.kernelModules = ["amdgpu"];
  security.polkit.extraConfig = ''
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
  services.xserver.videoDrivers = ["amdgpu"];

  programs = {
    steam.enable = true;
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


}