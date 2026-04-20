{
  pkgs,
  inputs,
  ...
}:

{
  programs.nix-index = {
    enable = true;
    package = inputs.nix-index-database.packages.${pkgs.system}.nix-index-with-db;
  };

  home.packages = [ pkgs.comma ];
}
