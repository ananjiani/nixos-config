_:

{

  home.sessionVariables = {
    EDITOR = "emacsclient -nw";
    NH_FLAKE = "/home/ammar/.dotfiles";
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
