# Experimental HDR niri (dividebysandwich fork + patched smithay).
# Not upstream. Remove when niri/smithay ship color-management.
# Track: https://github.com/niri-wm/niri/discussions/1128
#
# Source revs: nvfetcher (`niri-hdr`, `smithay-hdr` in nvfetcher.toml).
# cargoDeps outputHash: MANUAL — see comment on cargoDeps below.
{
  lib,
  niri,
  cargo,
  rustc,
  stdenvNoCC,
  cacert,
  fetchurl,
  fetchFromGitHub,
  fetchgit,
  dockerTools,
}:

let
  sources = import ../../_sources/generated.nix {
    inherit
      fetchurl
      fetchFromGitHub
      fetchgit
      dockerTools
      ;
  };

  niriSrc = sources.niri-hdr.src;
  smithaySrc = sources.smithay-hdr.src;
  niriRev = sources.niri-hdr.version; # git rev

  # Cargo.toml patches smithay as path = "../smithay". Fold both into one
  # src tree so cargoDeps / the build see a local path dep.
  combinedSrc = stdenvNoCC.mkDerivation {
    name = "niri-hdr-src";
    preferLocalBuild = true;
    allowSubstitutes = false;
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      cp -rT ${niriSrc} $out
      chmod -R u+w $out
      cp -rT ${smithaySrc} $out/vendor-smithay
      sed -i \
        -e 's|path = "../smithay"|path = "./vendor-smithay"|g' \
        -e 's|path = "../smithay/smithay-drm-extras"|path = "./vendor-smithay/smithay-drm-extras"|g' \
        $out/Cargo.toml
    '';
  };

  pname = "niri-hdr";
  version = "26.04-hdr";

  # ── cargoDeps FOD hash is NOT tracked by nvfetcher ─────────────────────
  # Why: nvfetcher only knows source tarballs/git revs. cargoDeps is a
  # fixed-output derivation whose content is `cargo vendor` of the full
  # crate graph (Cargo.lock + every crates.io dep). That tree changes when:
  #   - niri/smithay rev bumps and Cargo.lock changes
  #   - any transitive crate version moves
  # Nix needs the content hash *before* the network fetch (purity). Nothing
  # can compute it without actually running cargo vendor. So after an
  # nvfetcher bump that touches Cargo.lock:
  #   1. set outputHash below to lib.fakeHash (or all-A's)
  #   2. nix-build -E 'with import <nixpkgs> {}; (callPackage ./package.nix {}).cargoDeps'
  #   3. paste the "got: sha256-..." hash back here
  # ──────────────────────────────────────────────────────────────────────
  cargoDeps = stdenvNoCC.mkDerivation {
    name = "${pname}-${version}-vendor";
    src = combinedSrc;
    nativeBuildInputs = [
      cargo
      rustc
      cacert
    ];
    # FODs may access the network.
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];
    buildPhase = ''
      runHook preBuild
      export CARGO_HOME=$(mktemp -d)
      # Path dep (smithay) lives in $src/vendor-smithay; vendor only crates.io.
      mkdir -p $out
      cargo vendor --versioned-dirs --locked $out
      # cargoSetupPostPatchHook diffs this against $src/Cargo.lock.
      cp Cargo.lock $out/
      runHook postBuild
    '';
    installPhase = "true";
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-QmpUkzRZ9ooVj/2cI4uWEXQ0vYhM77Lgw9ao7SdjWmw=";
  };
in
niri.overrideAttrs (old: {
  inherit pname version;
  src = combinedSrc;
  inherit cargoDeps;

  # Stock nixpkgs niri may be older than this fork; service file only has bare `niri`.
  postPatch = ''
    patchShebangs resources/niri-session
    substituteInPlace resources/niri.service \
      --replace-fail 'niri' "$out/bin/niri"
  '';

  # Completions are for the `niri` binary name, not pname niri-hdr.
  postInstall = lib.replaceStrings [ "--cmd $pname" ] [ "--cmd niri" ] (old.postInstall or "");

  # Upstream versionCheckHook expects exact version string; ours is a fork tag.
  doInstallCheck = false;

  env = (old.env or { }) // {
    NIRI_BUILD_COMMIT = builtins.substring 0 7 niriRev;
  };

  meta = old.meta // {
    description = "niri with experimental HDR (dividebysandwich fork)";
    homepage = "https://github.com/niri-wm/niri/discussions/1128";
  };
})
