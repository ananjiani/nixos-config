# Shared Home Manager config for all server hosts
{
  imports = [
    ../profiles/essentials/home.nix
    ../../modules/home/terminal/monitoring.nix
  ];
}
