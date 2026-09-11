# Workstation-specific defaults (GUI apps, MIME types, etc.)
{ config, pkgs, ... }:

let
  # Steam has private /tmp; Brave singleton socket must use host /tmp.
  brave-origin-host = pkgs.writeShellScript "brave-origin-host" ''
    exec ${pkgs.systemd}/bin/systemd-run --user --quiet --collect -- ${pkgs.brave-origin}/bin/brave-origin "$@"
  '';
in
{
  home.sessionVariables = {
    EDITOR = "emacsclient -nw";
    HF_TOKEN = config.sops.secrets.hf_token.path;
  };

  xdg = {
    configFile."mimeapps.list".force = true;
    mimeApps = {
      enable = true;

      defaultApplications = {
        "text/html" = "brave-origin-host.desktop";
        "x-scheme-handler/http" = "brave-origin-host.desktop";
        "x-scheme-handler/https" = "brave-origin-host.desktop";
        "x-scheme-handler/about" = "brave-origin-host.desktop";
        "x-scheme-handler/unknown" = "brave-origin-host.desktop";
        "inode/directory" = "thunar.desktop";
        "text/org" = "emacsclient.desktop";
        "text/plain" = "emacsclient.desktop";
        "application/pdf" = "emacsclient.desktop";
      };
    };

    desktopEntries.brave-origin-host = {
      name = "Brave Origin";
      exec = "${brave-origin-host} %U";
      noDisplay = true;
      terminal = false;
      mimeType = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/about"
        "x-scheme-handler/unknown"
      ];
    };
  };
}
