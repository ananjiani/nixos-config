{
  ...
}:

{
  imports = [
    # Core terminal configuration (shells, CLI tools, etc.)
    #
    ../../hosts/profiles/essentials/home.nix
    ../../modules/home/terminal/core.nix

    # ../../modules/home/terminal/programs/atuin.nix

    # System monitoring tools
    ../../modules/home/terminal/monitoring.nix

    # # SOPS for secrets management
    # ../../modules/home/config/sops.nix
  ];

}
