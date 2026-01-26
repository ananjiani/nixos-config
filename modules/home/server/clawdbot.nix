# Clawdbot - Telegram AI Assistant
#
# Uses nix-clawdbot flake to run clawdbot as a Home Manager user service.
# Connects to Telegram and uses Bifrost LLM proxy for AI inference.
{
  config,
  lib,
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
  };
}
