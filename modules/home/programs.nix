{
  config,
  pkgs,
  lib,
  inputs,
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
      inputs.whisper-dictation.packages.${pkgs.system}.default
      youtube-music
      playerctl
    ]
  );

}
