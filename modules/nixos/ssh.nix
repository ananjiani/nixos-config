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

  # Centralized authorized keys management
  # These keys can SSH INTO any machine that imports this module
  users.users.ammar.openssh.authorizedKeys.keys = [
    # framework13 laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP1SNOPjx46qrONmD552cAcRg5zgcs9gRwClv7ayZoY1 framework13"

    # desktop key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMoo8KQiLBJ6WrWmG0/6O8lww/v6ggPaLfv70/ksMZbD ammar.nanjiani@gmail.com"

    # Desktop key will be added here after generation
  ];
}
