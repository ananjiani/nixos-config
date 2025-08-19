_:

{
  # Enable SSH server with secure defaults
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      PermitEmptyPasswords = false;
      MaxAuthTries = 3;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };
  };

  # Enable fail2ban for SSH protection
  services.fail2ban = {
    enable = true;
    bantime = "1h"; # Ban IPs for 1 hour
    bantime-increment = {
      enable = true; # Increase ban time for repeat offenders
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # Maximum ban time: 1 week
    };
    maxretry = 5; # Allow 5 failed attempts
    ignoreIP = [
      "127.0.0.1/8" # Localhost
      "10.0.0.0/8" # Private networks
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
  };

  # Centralized authorized keys management
  # These keys can SSH INTO any machine that imports this module
  users.users.ammar.openssh.authorizedKeys.keys = [
    # framework13 laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1SNOPjx46qrONmD552cAcRg5zgcs9gRwClv7ayZoY1 framework13"

    # desktop key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoo8KQiLBJ6WrWmG0/6O8lww/v6ggPaLfv70/ksMZbD ammar.nanjiani@gmail.com"

    # homeserver
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIASRuEYfCfFwqqIe3ef32mFK7kWMRgzZoTZrxg7B/0uL ammar@homeserver"
  ];
}
