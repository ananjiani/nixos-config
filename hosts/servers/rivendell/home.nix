{
  ...
}:

{
  imports = [
    # Core terminal configuration (shells, CLI tools, etc.)
    ../../../hosts/profiles/essentials/home.nix

    # System monitoring tools
    ../../../modules/home/terminal/monitoring.nix
  ];
}
