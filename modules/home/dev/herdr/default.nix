{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  herdrPkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./remote-file-paste.patch ];
  });

  # nvfetcher-tracked (herdr-reviewr, herdr-reviewr-bin). Depth matches
  # modules/home/dev/pi-coding-agent.nix plus one for herdr/.
  sources = import ../../../../_sources/generated.nix {
    inherit (pkgs)
      fetchurl
      fetchFromGitHub
      fetchgit
      dockerTools
      ;
  };
  reviewrPluginSrc = sources.herdr-reviewr.src;
  reviewrPluginArchive = sources.herdr-reviewr-bin.src;
  reviewrPluginRoot =
    pkgs.runCommand "herdr-reviewr-plugin"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        mkdir -p $out
        cp -a ${reviewrPluginSrc}/. $out/
        chmod -R u+w $out
        mkdir -p $out/bin
        tar -xzf ${reviewrPluginArchive} -C $out/bin
        chmod +x $out/bin/herdr-reviewr
      '';

  # yavuzhansarmaz/herdr-archive: park idle tabs, restore from a picker.
  archivePluginSrc = pkgs.fetchFromGitHub {
    owner = "yavuzhansarmaz";
    repo = "herdr-archive";
    rev = "d297c2ba2f933774828436e820cdc6883e8a9d05";
    hash = "sha256-ea6HSxn5EbJGiu6qr3V6AhL5vXhg6if+dGhIUmCaMyQ=";
  };
  archivePluginBin = pkgs.rustPlatform.buildRustPackage {
    pname = "herdr-archive";
    version = "0.1.0-unstable-2026-10-08";
    src = archivePluginSrc;
    cargoHash = "sha256-kDy/NlgGzsSoHucaRu43i+LKRs9G0n6LbeCGTPgTEBM=";
    # A DST test sets TZ=America/Los_Angeles; the sandbox has no zoneinfo.
    preCheck = "export TZDIR=${pkgs.tzdata}/share/zoneinfo";
  };
  # The manifest runs ./target/release/herdr-archive from the plugin root.
  archivePluginRoot = pkgs.runCommand "herdr-archive-plugin" { } ''
    mkdir -p $out/target/release
    cp ${archivePluginSrc}/herdr-plugin.toml $out/
    ln -s ${archivePluginBin}/bin/herdr-archive $out/target/release/herdr-archive
  '';

  # Link a Nix-pinned plugin when plugin_root drifts. herdr plugin link skips
  # [[build]], so activation never downloads or compiles anything.
  linkPlugin = id: root: ''
    want_root="${root}"
    have_root=""
    kind=""
    if [ -f "$plugins_json" ]; then
      have_root="$(jq -r --arg id "${id}" \
        '.[] | select(.plugin_id == $id) | .plugin_root // empty' \
        "$plugins_json" 2>/dev/null || true)"
    fi
    if [ "$have_root" != "$want_root" ]; then
      if [ -n "$have_root" ]; then
        kind="$(jq -r --arg id "${id}" \
          '.[] | select(.plugin_id == $id) | .source.kind // empty' \
          "$plugins_json" 2>/dev/null || true)"
        case "$kind" in
          github)
            run herdr plugin uninstall "${id}" 2>/dev/null || true
            ;;
          *)
            if ! run herdr plugin unlink "${id}" 2>/dev/null; then
              run herdr plugin uninstall "${id}" 2>/dev/null || true
            fi
            ;;
        esac
      fi
      # Warn, don't abort activation: an nvfetcher bump may need a newer herdr
      # server. Relink the previous local root so the plugin isn't lost.
      if ! run herdr plugin link "$want_root"; then
        echo "warning: herdr plugin link failed for ${id}" >&2
        if [ "$kind" != github ] && [ -n "$have_root" ] && [ -d "$have_root" ]; then
          run herdr plugin link "$have_root" \
            || echo "warning: could not restore ${id} from $have_root" >&2
        fi
      fi
    fi
  '';
in
{
  xdg.configFile."herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/modules/home/dev/herdr/config.toml";

  home = {
    packages = [ herdrPkg ];

    activation.linkHerdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${
        lib.makeBinPath [
          herdrPkg
          pkgs.jq
          pkgs.coreutils
        ]
      }:$PATH"
      plugins_json="$HOME/.config/herdr/plugins.json"
      ${linkPlugin "persiyanov.reviewr" reviewrPluginRoot}
      ${linkPlugin "herdr-archive" archivePluginRoot}
      # The status command exits successfully even when no server is running.
      status_json="$(herdr status server --json)"
      if printf '%s\n' "$status_json" | jq -e '.running == true' >/dev/null; then
        run herdr server reload-config
      fi
    '';
  };
}
