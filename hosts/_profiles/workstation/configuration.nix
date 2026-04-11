# Workstation profile — shared by desktop and laptop hosts
# Imports base.nix for universal foundation, adds workstation-specific config
{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../base.nix
    ../secrets.nix
    ../../../modules/nixos/fonts.nix
    ../../../modules/nixos/privacy.nix
  ];

  # Desktop compositor via dendritic module
  desktop.hyprland.enable = lib.mkDefault true;

  # vault-agent runtime secrets for the claude-kimi / claude-glm fish
  # wrappers (see modules/home/dev/claude-code.nix). All three reuse
  # k8s-canonical paths via the vault-agent cross-boundary pattern —
  # single source of truth, no mirroring. Each path must be explicitly
  # granted in terraform/openbao.tf vault_policy.vault_agent.
  modules.vault-agent.secrets = {
    # Bifrost default VK used by `claude-kimi`.
    bifrost_api_key = {
      path = "secret/k8s/bifrost";
      field = "default-virtual-key";
      owner = "ammar";
      mode = "0400";
    };

    # z.ai API key used by `claude-glm`. Bifrost can't proxy z.ai's
    # Anthropic endpoint (Responses-API translation mismatch), so the
    # wrapper hits api.z.ai directly.
    zai_api_key = {
      path = "secret/k8s/bifrost";
      field = "zai-api-key";
      owner = "ammar";
      mode = "0400";
    };

    # Tavily API key for the Tavily MCP server wired into both wrappers
    # as an external WebSearch replacement (neither z.ai nor Bifrost/
    # cliproxy can proxy Anthropic's server-side web_search_20250305
    # tool). Reused from open-webui's existing k8s secret.
    tavily_api_key = {
      path = "secret/k8s/open-webui";
      field = "tavily-api-key";
      owner = "ammar";
      mode = "0400";
    };
  };

  programs = {
    nh = {
      enable = true;
      flake = "~/.dotfiles";
    };
    kdeconnect.enable = true;
    gnupg.agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      enableSSHSupport = true;
    };
  };

  # Workstation networking (servers use systemd-networkd or DHCP)
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved"; # Use systemd-resolved for split DNS
    };
    firewall.allowedTCPPorts = [ 22 ]; # SSH
  };

  # Split DNS: route .lan queries to OPNsense, everything else through VPN
  services = {
    resolved = {
      enable = true;
      domains = [
        "~lan" # Route .lan to fallback DNS
        # Route ts.dimensiondoor.xyz and other dimensiondoor.xyz subdomains
        # to AdGuard so split-DNS rewrites win over wg0-mullvad's `~.` catch-all.
        # Defense in depth for the 2026-04-07/2026-04-10 Mullvad DNS saga.
        "~dimensiondoor.xyz"
      ];
      fallbackDns = [ "192.168.1.1" ]; # OPNsense for .lan resolution
    };
    pcscd.enable = true;
  };

  environment.systemPackages = with pkgs; [
    fastfetch
  ];

  # Add workstation-specific groups
  users.users.ammar.extraGroups = [
    "docker"
  ];

  # EFI boot loader (all workstations use systemd-boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security = {
    polkit.enable = true;
    rtkit.enable = true;
  };

  system.stateVersion = "23.05";
}
