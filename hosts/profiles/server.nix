# Server profile — shared by all server hosts
# (boromir, samwise, theoden, erebor, rivendell)
{
  inputs,
  pkgs-stable,
  ...
}:

{
  imports = [
    inputs.home-manager-unstable.nixosModules.home-manager
  ];

  # Prometheus node exporter for monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };

  # Home Manager — shared server config
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs pkgs-stable; };
    users.ammar = import ../servers/home.nix;
  };

  system.stateVersion = "25.11";
}
