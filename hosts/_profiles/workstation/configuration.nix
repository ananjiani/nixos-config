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

  # LLM API keys from consolidated Bao path (secret/llm/keys).
  # Used by claude-kimi/claude-glm fish wrappers and pi coding agent.
  # See terraform/openbao.tf vault_policy.vault_agent for the llm/* grant.
  modules.vault-agent.secrets = {
    # Kimi Code (api.kimi.com/coding) membership key used by `claude-kimi`.
    kimi_code_api_key = {
      path = "secret/llm/keys";
      field = "kimi-code-api-key";
      owner = "ammar";
      mode = "0400";
    };

    # z.ai API key used by `claude-glm`. Bifrost can't proxy z.ai's
    # Anthropic endpoint (Responses-API translation mismatch), so the
    # wrapper hits api.z.ai directly.
    zai_api_key = {
      path = "secret/llm/keys";
      field = "zai-api-key";
      owner = "ammar";
      mode = "0400";
    };

    # Tavily API key for the Tavily MCP server wired into both wrappers
    # as an external WebSearch replacement (neither z.ai nor Kimi Code
    # can proxy Anthropic's server-side web_search_20250305 tool).
    tavily_api_key = {
      path = "secret/llm/keys";
      field = "tavily-api-key";
      owner = "ammar";
      mode = "0400";
    };

    # OpenCode Go API key for pi coding agent ($10/month subscription
    # to open coding models via opencode.ai/zen/go/v1).
    opencode_api_key = {
      path = "secret/llm/keys";
      field = "opencode-api-key";
      owner = "ammar";
      mode = "0400";
    };

    # OpenCode Go dashboard workspace ID and browser auth cookie.
    # Used by the usage-tracker extension to scrape exact quota
    # percentages (rolling/weekly/monthly) from the OpenCode dashboard.
    # The workspace ID is visible in the browser URL bar at
    # https://opencode.ai/workspace/<id>/go — not sensitive but
    # colocated with the cookie for simplicity. The auth cookie is
    # the `auth` cookie for opencode.ai from browser devtools.
    opencode_go_workspace_id = {
      path = "secret/llm/keys";
      field = "opencode-go-workspace-id";
      owner = "ammar";
      mode = "0400";
    };
    opencode_go_auth_cookie = {
      path = "secret/llm/keys";
      field = "opencode-go-auth-cookie";
      owner = "ammar";
      mode = "0400";
    };

    # NVIDIA NIM API key for pi coding agent (build.nvidia.com).
    nvidia_nim_api_key = {
      path = "secret/llm/keys";
      field = "nvidia-nim-api-key";
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

  services = {
    resolved = {
      enable = true;
      # No explicit routing domains — Tailscale's ~. catch-all (DefaultRoute)
      # handles both .lan and dimensiondoor.xyz via Headscale split-DNS, which
      # points both to AdGuard on Tailscale IPs (reachable on-LAN and off-LAN).
      fallbackDns = [ "192.168.1.1" ];
    };
    pcscd.enable = true;
  };

  environment = {
    systemPackages = with pkgs; [
      fastfetch
    ];
    etc."claude-code/managed-settings.d/10-security.json".text = builtins.toJSON {
      permissions.deny = [
        "Bash(sops -d:*)"
        "Bash(sops --decrypt:*)"
      ];
      hooks.PreToolUse = [
        {
          hooks = [
            {
              type = "command";
              command = "~/.claude/hooks/src/pre_tool_use.py";
            }
          ];
        }
      ];
    };
  };

  # Add workstation-specific groups
  users.users.ammar.extraGroups = [
    "docker"
  ];

  # Steam's 32-bit helper binaries trigger split lock traps (unaligned atomics
  # spanning cache lines) which the kernel throttles by default since 5.19,
  # causing system-wide stalls. Set to warn-only — still logs but no penalty.
  # steam-for-linux#13037, #8003, #11740; Phoronix 2022-12-13
  boot = {
    kernelModules = [ "ntsync" ];
    kernelParams = [ "split_lock_detect=warn" ];
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
  };

  security = {
    polkit.enable = true;
    rtkit.enable = true;
  };

  system.stateVersion = "23.05";

  # Local + distributed builds: build locally on the 9800X3D (fastest per-core),
  # overflow heavy/parallel work to theoden + boromir.
  # i686-linux is included so FHS envs (lutris, steam) can delegate 32-bit builds.
  # speedFactor 1 makes local jobs preferred; remote builders pick up when local
  # slots are full or for i686-only derivations.
  nix = {
    distributedBuilds = true;
    settings = {
      max-jobs = 8;
      builders-use-substitutes = true;
    };
    buildMachines = [
      {
        hostName = "theoden.lan";
        systems = [
          "x86_64-linux"
          "i686-linux"
        ];
        sshUser = "root";
        sshKey = "/home/ammar/.ssh/id_ed25519";
        maxJobs = 4;
        speedFactor = 1;
        supportedFeatures = [
          "nixos-test"
          "big-parallel"
          "kvm"
        ];
      }
      {
        hostName = "boromir.lan";
        systems = [
          "x86_64-linux"
          "i686-linux"
        ];
        sshUser = "root";
        sshKey = "/home/ammar/.ssh/id_ed25519";
        maxJobs = 3;
        speedFactor = 1;
        supportedFeatures = [
          "nixos-test"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };
}
