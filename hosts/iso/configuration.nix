# Live USB / Installation ISO configuration
{
  lib,
  modulesPath,
  inputs,
  ...
}:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
    ../../modules/nixos/base.nix
    ../../modules/nixos/ssh.nix
    inputs.disko.nixosModules.disko
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # SSH with permissive settings for installation
  modules.ssh = {
    enable = true;
    passwordAuth = true;
    permitRootLogin = "yes";
  };

  # Override the empty password from installation-cd-minimal.nix
  users.users.root = {
    initialHashedPassword = lib.mkForce null;
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoo8KQiLBJ6WrWmG0/6O8lww/v6ggPaLfv70/ksMZbD ammar.nanjiani@gmail.com"
    ];
  };

  # Extra tools available via: nix shell nixpkgs#parted nixpkgs#gptfdisk etc.
}
