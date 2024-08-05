{ config, pkgs, lib, pkgs-stable, ... }:

{
  boot.initrd.kernelModules = [ "amdgpu" ];
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Enable Settings for AMD
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs-stable.rocmPackages.clr}"
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs-stable; [
      rocm-opencl-icd
      rocm-opencl-runtime
      #amdvlk
      #driversi686Linux.amdvlk
    ];
  };

  environment.systemPackages = with pkgs; [ corectrl ];

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
