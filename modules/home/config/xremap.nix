{ inputs, ... }:

{
  imports = [ inputs.xremap.homeManagerModules.default ];

  services.xremap = {
    withWlroots = true;
    config.modmap = [
      {
        name = "main remaps";
        remap.CapsLock = "CONTROL_L";
      }
    ];
  };
}
