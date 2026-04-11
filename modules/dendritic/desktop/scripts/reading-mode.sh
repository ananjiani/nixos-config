#!/usr/bin/env bash
# Reading mode: open Readwise Reader, an Emacs frame, and a Claude Code
# research companion side-by-side on the dedicated niri reading workspace.
#
# Layout on 32:9 ultrawide:
#   [ Readwise Reader (1/2) ][ Emacs (1/4) ][ Claude Code (1/4) ]
#
# Window routing is handled by focus-workspace + niri auto-focusing each
# new window. Column widths are set imperatively after each spawn rather
# than via window rules, because Brave on Wayland ignores --class, Doom's
# frame-title-format overrides explicit frame names, and foot's --app-id
# was observed to be ignored in this setup — leaving nothing reliable to
# match on in window rules. Setting the focused column's width right after
# the spawn sidesteps all of that.

set -euo pipefail

WORKSPACE="05-reading"
ORG_ROAM_DIR="$HOME/Documents/org-roam"

# Wait until niri reports a newly-focused window whose App ID matches the
# regex $1, up to $2 seconds. Polls the JSON output of `niri msg -j
# focused-window` every 100ms. Returns 0 on match, 1 on timeout.
wait_focused() {
    local app_re="$1"
    local timeout="${2:-8}"
    local deadline=$(($(date +%s) + timeout))
    while [[ $(date +%s) -lt $deadline ]]; do
        if niri msg -j focused-window 2>/dev/null \
            | grep -Eq "\"app_id\"[[:space:]]*:[[:space:]]*\"${app_re}\""; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Jump to the reading workspace first so every new window lands here.
niri msg action focus-workspace "$WORKSPACE"

# 1. Readwise Reader as a Brave PWA-style window (left half).
brave --app="https://read.readwise.io" >/dev/null 2>&1 &
wait_focused "brave-browser" 10 || true
niri msg action set-column-width "50%"

# 2. Emacs frame from the running daemon (next quarter). -n returns
#    immediately; the frame pops up asynchronously via the daemon.
emacsclient -c -n
wait_focused "emacs" 5 || true
niri msg action set-column-width "25%"

# 3. Claude Code rooted in org-roam as a research companion (last quarter).
#    fish -C runs claude at startup and drops back to an interactive shell
#    if it exits.
foot --working-directory="$ORG_ROAM_DIR" fish -C claude >/dev/null 2>&1 &
wait_focused "foot" 5 || true
niri msg action set-column-width "25%"

exit 0
