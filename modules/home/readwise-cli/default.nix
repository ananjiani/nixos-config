{ pkgs, ... }:

pkgs.buildNpmPackage {
  pname = "readwise-cli";
  version = "0.5.6";
  src = ./.;
  packageJson = ./package.json;
  npmDepsHash = "sha256-+k8bwIvhaaAW/Iryrv+U1UbYecXlCc2yqboldT1CMaQ=";
  dontNpmBuild = true;

  postInstall = ''
    mkdir -p $out/bin
    cat > $out/bin/readwise << SCRIPT
    #!/bin/sh
    exec ${pkgs.nodejs}/bin/node $out/lib/node_modules/readwise-cli-wrapper/node_modules/@readwise/cli/dist/index.js "\\$@"
    SCRIPT
    chmod +x $out/bin/readwise
  '';
}
