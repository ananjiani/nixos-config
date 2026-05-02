{ pkgs, ... }:

pkgs.buildNpmPackage {
  pname = "readwise-cli";
  version = "0.5.6";
  src = ./.;
  packageJson = ./package.json;
  npmDepsHash = "sha256-SFXYeSuq3w6vHra1JSgM8BZu8TzXwCkS9ALyjbNKrhE=";
  dontNpmBuild = true;

  postInstall = ''
    mkdir -p $out/bin
    cat > $out/bin/readwise << 'SCRIPT'
    #!/bin/sh
    exec ${pkgs.nodejs}/bin/node ${placeholder "out"}/lib/node_modules/readwise-cli-wrapper/node_modules/@readwise/cli/dist/index.js "$@"
    SCRIPT
    chmod +x $out/bin/readwise
  '';
}
