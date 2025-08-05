# Workstation-specific defaults (GUI apps, MIME types, etc.)
{ config, ... }:

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
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/about" = "firefox.desktop";
        "x-scheme-handler/unknown" = "firefox.desktop";
        "inode/directory" = "thunar.desktop";
        "text/org" = "emacsclient.desktop";
        "text/plain" = "emacsclient.desktop";
        "application/pdf" = "emacsclient.desktop";
      };
    };
  };
}
