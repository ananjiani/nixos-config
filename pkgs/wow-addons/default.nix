{ pkgs, sources }:
let
  inherit (pkgs) lib;
  mkAddon =
    name: source:
    pkgs.runCommand name
      {
        inherit (source) src;
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${./unpack.py} "$src" "$out"
      '';
in
lib.mapAttrsToList mkAddon (lib.filterAttrs (name: _: lib.hasPrefix "wow-" name) sources)
