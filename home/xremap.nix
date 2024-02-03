{ pkgs, xremap, ...}:

{
  imports = [
    xremap.homeManagerModules.default
  ];

  services.xremap = {
    withHypr = true;
    config.modmap = [
        {
          name = "main remaps";
          remap.CapsLock = "CONTROL_L";
        }
    ];
  };
}
