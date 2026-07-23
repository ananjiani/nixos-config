# Aragorn - Devbox / homelab command center (Proxmox VM on gondor)
#
# Always-on sandbox for coding agents (pi, claude), reachable over
# Tailscale. Holds a ~/.dotfiles checkout and runs deploy-rs / heavy
# nix builds so the desktop doesn't have to.
{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ../../_profiles/server/proxmox-disk-config.nix
    ../../_profiles/server/configuration.nix
    ../../../modules/nixos/networking.nix
  ];

  networking.hostName = "aragorn";

  # Plain tailnet client — not routing infrastructure
  modules = {
    tailscale = {
      exitNode = false;
      subnetRoutes = [ ];
    };

    # API keys consumed by the Pi and Claude wrapper configurations.
    vault-agent.secrets = {
      kimi_code_api_key = {
        path = "secret/llm/keys";
        field = "kimi-code-api-key";
        owner = "ammar";
      };
      zai_api_key = {
        path = "secret/llm/keys";
        field = "zai-api-key";
        owner = "ammar";
      };
      tavily_api_key = {
        path = "secret/llm/keys";
        field = "tavily-api-key";
        owner = "ammar";
      };
      opencode_api_key = {
        path = "secret/llm/keys";
        field = "opencode-api-key";
        owner = "ammar";
      };
    };
  };

  # Keep the user manager alive for persistent agent sessions and user secrets.
  users.users.ammar.linger = true;

  # Dev/agent tooling on top of the minimal shared server home profile.
  home-manager.users.ammar = {
    imports = [
      inputs.stylix.homeModules.stylix
      inputs.sops-nix.homeManagerModules.sops
      ../../../modules/home/dev/pi-coding-agent.nix
      ../../../modules/home/dev/claude-code.nix
      ../../../modules/home/dev/nix-direnv.nix
      ../../../modules/home/dev/tea.nix
      ../../../modules/home/dev/lang/python.nix
      ../../../modules/home/dev/lang/nixlang.nix
      ../../../modules/home/dev/nix-index.nix
      ../../../modules/home/dev/programs.nix
    ];

    sops = {
      age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
      defaultSopsFile = ../../../secrets/secrets.yaml;
      defaultSymlinkPath = "/run/user/1000/secrets";
      defaultSecretsMountPoint = "/run/user/1000/secrets.d";
    };

    # Pi consumes config.lib.stylix.colors, but a headless server must not
    # activate Stylix's KDE/dconf targets.
    stylix = {
      enable = false;
      base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-soft.yaml";
      polarity = "dark";
    };
  };
}
