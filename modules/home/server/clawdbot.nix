# Clawdbot - Telegram AI Assistant
#
# Uses nix-clawdbot flake to run clawdbot as a Home Manager user service.
# Connects to Telegram and uses Bifrost LLM proxy for AI inference.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.modules.clawdbot;
in
{
  imports = [ inputs.nix-clawdbot.homeManagerModules.clawdbot ];

  options.modules.clawdbot = {
    enable = lib.mkEnableOption "Clawdbot Telegram AI assistant";

    telegramUserId = lib.mkOption {
      type = lib.types.int;
      description = "Telegram user ID allowed to interact with the bot";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.clawdbot = {
      enable = true;

      # Disable macOS-only plugins that break nix flake check on Linux
      firstParty = {
        peekaboo.enable = false;
        summarize.enable = false;
      };

      instances.default = {
        enable = true;

        providers.telegram = {
          enable = true;
          botTokenFile = config.sops.secrets.telegram_bot_token.path;
          allowFrom = [ cfg.telegramUserId ];
        };

        providers.anthropic = {
          apiKeyFile = config.sops.secrets.bifrost_api_key.path;
        };
      };
    };

    # Override activation scripts to use Nix store paths instead of /bin/mkdir
    # Workaround for https://github.com/clawdbot/nix-clawdbot/pull/1
    home.activation.clawdbotDirs = lib.mkForce (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.coreutils}/bin/mkdir -p "$HOME/.clawdbot" "$HOME/.clawdbot/workspace"
      ''
    );

    home.activation.clawdbotConfigFiles = lib.mkForce (
      lib.hm.dag.entryAfter [ "clawdbotDirs" ] ''
        set -euo pipefail
        # Config is managed by home.file, no manual linking needed
      ''
    );
  };
}
