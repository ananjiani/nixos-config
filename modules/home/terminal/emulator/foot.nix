{ pkgs, ... }:

let
  # Foot's stock notify-send can't focus the originating window (no XDG
  # activation token), so on "default" activation we look up the foot window
  # by PID ($PPID of this wrapper) in niri and focus it directly.
  footNotify = pkgs.writeShellApplication {
    name = "foot-notify";
    runtimeInputs = with pkgs; [
      libnotify
      niri
      jq
      systemd
    ];
    text = ''
      if [ "''${1:-}" = "--close" ]; then
        exec busctl --user call org.freedesktop.Notifications \
          /org/freedesktop/Notifications org.freedesktop.Notifications \
          CloseNotification u "$2"
      fi

      foot_pid=$PPID
      notify-send -a "$1" -i "$2" -c "$3" -u "$4" -t "$5" -r "$6" \
        --wait --action=default=Activate --print-id -- "$7" "$8" |
        while IFS= read -r line; do
          printf '%s\n' "$line"
          if [ "$line" = "default" ] || [ "$line" = "action=default" ]; then
            win=$(niri msg --json windows |
              jq -r --argjson pid "$foot_pid" \
                'first(.[] | select(.pid == $pid) | .id) // empty') || true
            if [ -n "$win" ]; then
              niri msg action focus-window --id "$win" || true
            fi
          fi
        done
    '';
  };
in
{
  programs.foot = {
    enable = true;
    settings = {
      main = {
        shell = "fish";
        term = "xterm-256color";
        font = "hack:size=14";
      };

      desktop-notifications = {
        command = "${footNotify}/bin/foot-notify \${app-id} \${icon} \${category} \${urgency} \${expire-time} \${replace-id} \${title} \${body}";
        close = "${footNotify}/bin/foot-notify --close \${id}";
      };

      colors-dark = {
        background = "282828";
        foreground = "ebdbb2";
        regular0 = "282828";
        regular1 = "cc241d";
        regular2 = "98971a";
        regular3 = "d79921";
        regular4 = "458588";
        regular5 = "b16286";
        regular6 = "689d6a";
        regular7 = "a89984";
        bright0 = "928374";
        bright1 = "fb4934";
        bright2 = "b8bb26";
        bright3 = "fabd2f";
        bright4 = "83a598";
        bright5 = "d3869b";
        bright6 = "8ec07c";
        bright7 = "ebdbb2";
      };
    };
  };

}
