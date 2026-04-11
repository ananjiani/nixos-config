#!/usr/bin/env bash
# Reading mode: open Readwise Reader, an Emacs frame, and a Claude Code
# research companion side-by-side on a dedicated niri workspace.
#
# Layout on 32:9 ultrawide:
#   [ Readwise Reader (1/2) ][ Emacs (1/4) ][ Claude Code (1/4) ]
#
# Workspace routing and column widths are set by niri window rules keyed on
# app-id / title; this script just focuses the workspace and spawns each app
# in order so they end up in the correct left-to-right column order.

set -euo pipefail

WORKSPACE="05-reading"
ORG_ROAM_DIR="$HOME/Documents/org-roam"

# Jump to the reading workspace first so any new windows without an explicit
# open-on-workspace rule (e.g. the Emacs frame) also land here.
niri msg action focus-workspace "$WORKSPACE"

# 1. Readwise Reader as a PWA-style window. --class sets the Wayland app-id
#    so the niri window rule can size it to half the screen.
brave --app="https://read.readwise.io" --class="readwise-reader" &
sleep 1.5

# 2. Emacs frame with a distinctive, locked title so the niri rule can match
#    just this frame and size it to a quarter. explicit-name prevents
#    frame-title-format from overwriting the name with the buffer name.
emacsclient -c -n \
    -F '((name . "reading-companion") (explicit-name . t))'
sleep 0.4

# 3. Claude Code as a research companion, rooted in org-roam. --app-id tags
#    the window for the niri rule. fish -C runs claude at startup and leaves
#    an interactive shell behind if it exits.
foot \
    --app-id=claude-reading \
    --working-directory="$ORG_ROAM_DIR" \
    fish -C claude &

exit 0
