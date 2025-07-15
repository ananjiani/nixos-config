{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.packages = (
    with pkgs;
    [
      xcolor
      inkscape
      pinta
      vlc
      xfce.thunar
      xfce.thunar-archive-plugin
      xfce.thunar-media-tags-plugin
      obs-studio
      gst_all_1.gstreamer
      obs-studio-plugins.obs-gstreamer
      obs-studio-plugins.obs-vkcapture
      libva-utils
      cmatrix
      ungoogled-chromium
      google-chrome
      element-desktop
      xournalpp
      openai-whisper
      uv
      ntfy
    ]
  );

}
