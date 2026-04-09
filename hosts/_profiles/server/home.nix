# Shared Home Manager config for all server hosts
{
  imports = [
    ../essentials/home.nix
    ../../../modules/home/terminal/monitoring.nix
  ];
}
