{
  pkgs,
  ...
}:
{

  home.shellAliases = {
    vi = "lvim";
    vim = "lvim";
    vimdiff = "lvim -d";
  };

  home.packages = with pkgs; [
    lunarvim
  ];
}
