# Org-roam Syncthing folder on ammars-pc, framework13, and aragorn.
# Host home configs pair ammars-pc and framework13; aragorn stays unpaired.
# The empty folder.devices below merges with host-specific peer lists.
# Manual sharing on declared folders is overwritten.
# overrideDevices/overrideFolders = false preserve undeclared
# devices/folders only, not declared folder membership. Future game-saves
# peers must also be declared in Nix. Staggered versioning is not a backup.
{ config, ... }:

{
  home.file."Documents/org-roam/.stignore".text = ''
    // VCS internals
    .git
    .jj
    // Editor locks
    (?d).~lock.*
    (?d).#*
    (?d)*.swp
    (?d).hugo_build.lock
    // Generated Hugo output
    (?d)writing/blog/public
    (?d)writing/blog/**/resources/_gen
    // Generated quartz output
    (?d)rpg/gnosis/quartz/node_modules
    (?d)rpg/gnosis/quartz/public
  '';

  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
    guiAddress = "127.0.0.1:8384";
    settings = {
      folders = {
        org-roam = {
          id = "org-roam";
          label = "org-roam";
          path = "${config.home.homeDirectory}/Documents/org-roam";
          type = "sendreceive";
          devices = [ ];
          versioning = {
            type = "staggered";
            params.maxAge = "2592000"; # 30 days
          };
        };
      };
    };
  };
}
