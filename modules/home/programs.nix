{
  pkgs,
  pkgs-stable,
  inputs,
  ...
}:

{
  home.packages = with pkgs; [
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
    # ungoogled-chromium Commented out because it takes one million years to build
    google-chrome
    xournalpp
    openai-whisper
    pkgs-stable.whisperx
    uv
    inputs.whisper-dictation.packages.${pkgs.system}.default
    youtube-music
    playerctl
    qbittorrent
  ];

  services = {
    kdeconnect = {
      enable = true;
      indicator = true;
    };
    etesync-dav.enable = true;
  };
  # programs.element-desktop.enable = true;

}
