{ config, pkgs, lib, ...}:

{
  services.blueman.enable = true;

  hardware = {
    bluetooth = {
      enable = true;
      # package = pkgs.pulseaudioFull;
      powerOnBoot = true;
      # settings = {
      #   General = {
      #     Experimental = true;
      #   };
      # };
    };
  };

  environment.etc = {
    "wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
      bluez_monitor.properties = {
        ["bluez5.enable-sbc-xq"] = true,
        ["bluez5.enable-msbc"] = true,
        ["bluez5.enable-hw-volume"] = true,
        ["bluez5.autoswitch-profile"] = true,
        ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
      }
    '';
  };
}