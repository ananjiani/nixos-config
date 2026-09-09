# Jellyfin media server (https://jellyfin.org)
#
# Native NixOS module (nixarr deliberately not used: its jellyfin extras are
# public-exposure/VPN plumbing that this LAN setup does not need — see repo
# history, the Aug 2025 nixarr experiment). State in /var/lib/jellyfin
# (local disk). Media read from the mergerfs pool at /mnt/storage/movies
# (library path set in the web wizard).
#
# No GPU on theoden: transcoding is CPU-only; fine for DVD-bitrate rips.
# Exposed on :8096, fronted by k3s traefik at https://jellyfin.lan and
# https://jellyfin.dimensiondoor.xyz (IngressRoute + manual Endpoints to
# 192.168.1.27 — k8s/apps/jellyfin/, follows the romm pattern).
_: {
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Read access to /mnt/storage/movies (storage group, gid 1500 — storage.nix)
  users.users.jellyfin.extraGroups = [ "storage" ];
}
