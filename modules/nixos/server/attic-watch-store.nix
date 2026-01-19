{
  config,
  lib,
  pkgs-stable,
  ...
}:

let
  cfg = config.services.attic-watch-store;
  hostname = config.networking.hostName;
  # Use localhost if we're on theoden (where atticd runs), otherwise use theoden.lan
  endpoint = if hostname == "theoden" then "http://localhost:8080" else "http://theoden.lan:8080";
in
{
  options.services.attic-watch-store = {
    enable = lib.mkEnableOption "Attic watch-store service to push builds to binary cache";
  };

  config = lib.mkIf cfg.enable {
    # Ensure the push token secret exists
    sops.secrets.attic_push_token = {
      mode = "0400";
    };

    systemd.services.attic-watch-store = {
      description = "Attic Watch Store - Push builds to binary cache";
      after = [ "network.target" ] ++ lib.optional (hostname == "theoden") "atticd.service";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs-stable.attic-client ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
      };
      script = ''
        # Configure Attic with the push token
        mkdir -p ~/.config/attic
        cat > ~/.config/attic/config.toml << EOF
        default-server = "local"

        [servers.local]
        endpoint = "${endpoint}"
        token = "$(cat ${config.sops.secrets.attic_push_token.path})"
        EOF
        chmod 600 ~/.config/attic/config.toml

        # Watch store and push new paths to middle-earth cache
        exec attic watch-store local:middle-earth
      '';
    };
  };
}
