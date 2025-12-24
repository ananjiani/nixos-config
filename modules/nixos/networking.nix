{
  pkgs-stable,
  ...
}:

{

  environment.systemPackages = with pkgs-stable; [
    nftables
    dig
  ];
}
