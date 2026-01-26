# Pippin Home Manager configuration
#
# Runs clawdbot as a user service for Telegram AI assistant functionality.
{ inputs, ... }:

{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
    ../../../hosts/profiles/essentials/home.nix
    ../../../modules/home/server/clawdbot.nix
  ];

  sops = {
    age.keyFile = "/home/ammar/.config/sops/age/keys.txt";
    defaultSopsFile = ../../../secrets/secrets.yaml;
    secrets = {
      telegram_bot_token = { };
      bifrost_api_key = { };
    };
  };

  modules.clawdbot = {
    enable = true;
    # TODO: Replace with your Telegram user ID from @userinfobot
    telegramUserId = 0;
  };
}
