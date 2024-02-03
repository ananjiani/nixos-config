{ pkgs, xremap, ...}:

{
  imports = [
    xremap.homeManagerModules.default
  ];

  services.xremap = {
    withHypr = true;
    userName = "ammar";
    config.modmap = [
        {
          name = "main remaps";
          remap.CapsLock = "CONTROL_L";
        }
    ];
  };
}
