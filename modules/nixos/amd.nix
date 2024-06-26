{ config, pkgs, lib, ... }:

{
  boot.initrd.kernelModules = ["amdgpu"];
  services.xserver.videoDrivers = ["amdgpu"];

  # Enable Settings for AMD
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      rocm-opencl-icd
      rocm-opencl-runtime
      #amdvlk
      #driversi686Linux.amdvlk
    ];
  };

  environment.systemPackages = with pkgs; [
    corectrl
  ];

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
}