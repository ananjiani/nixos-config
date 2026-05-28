# Dendritic Hydra Module
# Hydra Launcher - DRM-free game acquisition with TorBox integration
_:

let
  mkHydraAppImage =
    pkgs:
    let
      sources = import ../../_sources/generated.nix {
        inherit (pkgs)
          fetchurl
          fetchFromGitHub
          fetchgit
          dockerTools
          ;
      };
    in
    pkgs.appimageTools.wrapType2 {
      pname = "hydra-launcher";
      inherit (sources.hydra-launcher) version src;
      extraPkgs = _pkgs: [ ]; # No extra dependencies needed
    };
in
{
  flake.aspects.hydra.homeManager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.hydra = {
        enable = lib.mkEnableOption "Hydra Launcher";
      };
      config = lib.mkIf config.hydra.enable {
        home.packages = [ (mkHydraAppImage pkgs) ];
      };
    };
}
