{
  pkgs-stable,
  ...
}:

{
  environment.systemPackages = with pkgs-stable; [
    nftables
    dig
  ];

  # Local network hosts for faster resolution (backup to AdGuard DNS)
  networking.hosts = {
    "192.168.1.20" = [
      "gondor"
      "gondor.lan"
    ];
    "192.168.1.21" = [
      "boromir"
      "boromir.lan"
    ];
    "192.168.1.22" = [
      "faramir"
      "faramir.lan"
    ];
    "192.168.1.23" = [
      "the-shire"
      "the-shire.lan"
    ];
    "192.168.1.24" = [
      "rohan"
      "rohan.lan"
    ];
    "192.168.1.25" = [
      "frodo"
      "frodo.lan"
    ];
    "192.168.1.26" = [
      "samwise"
      "samwise.lan"
    ];
  };
}
