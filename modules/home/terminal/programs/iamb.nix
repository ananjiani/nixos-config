{ config, lib, pkgs, std, ... }:

{
  home.packages = with pkgs; [ iamb ];

  home.file = {
    ".config/iamb/config.toml".text = std.serde.toTOML {
      profiles."matrix.org" = { user_id = "@ammarn:matrix.org"; };
      settings.notifications.enabled = true;
    };
  };
}
