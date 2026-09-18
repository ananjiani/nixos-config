# Local copy of nix-community/buildbot-nix packages/buildbot-packages.nix
# at d193d375fe5c4be29f13dc34552903cae6813b07.
#
# Upstream interpolates "${pkgs.path}/pkgs/...". Nix 2.34 recopies nixpkgs to
# an unrooted store path; GC deletes it and Theoden eval fails
# `path ...-source is not valid`. Path addition (`pkgs.path + "/..."`) avoids
# the recopy. Stopgap until upstream drops the string interpolation.
{
  pkgs,
  lib,
  newScope,
  inputs,
}:
let
  # Patch twisted to handle ENOENT in epoll reactor when fd is closed before registration.
  # This fixes HTTP 502 errors caused by a race condition where a connection is accepted
  # but reset by the peer before the reactor can register it with epoll.
  python3 = pkgs.python3.override {
    packageOverrides = _final: prev: {
      twisted = prev.twisted.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (inputs.buildbot-nix + "/patches/twisted-epoll-enoent.patch")
        ];
      });
    };
  };
in
lib.makeScope (self: newScope (self.python.pkgs // self)) (self: {
  python = python3;
  buildbot-pkg = self.callPackage (
    pkgs.path + "/pkgs/development/tools/continuous-integration/buildbot/pkg.nix"
  ) { };
  buildbot-worker = self.callPackage (
    pkgs.path + "/pkgs/development/tools/continuous-integration/buildbot/worker.nix"
  ) { };
  buildbot = self.callPackage (
    pkgs.path + "/pkgs/development/tools/continuous-integration/buildbot/master.nix"
  ) { };
  buildbot-plugins = lib.recurseIntoAttrs (
    self.callPackage (
      pkgs.path + "/pkgs/development/tools/continuous-integration/buildbot/plugins.nix"
    ) { }
  );
})
