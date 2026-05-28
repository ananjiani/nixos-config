#!/bin/bash

# Launch Microsoft Edge with Outlook and Teams on weekdays only, before 5pm
# Uses Mullvad split tunneling.
#
# On Hyprland: explicitly placed on workspace 4 via hyprctl dispatch.
# On niri: launched normally; window rule open-on-workspace="work" routes it.

EDGE_CMD="mullvad-exclude flatpak run com.microsoft.Edge https://outlook.office365.com https://teams.microsoft.com"

# Check if today is a weekday (Monday=1, Sunday=7)
day_of_week=$(date +%u)

# Check current hour (24-hour format)
current_hour=$(date +%H)

# Only run Monday through Friday (1-5) and before 5pm (17:00)
if [ "$day_of_week" -le 5 ] && [ "$current_hour" -lt 17 ]; then
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        hyprctl dispatch exec "[workspace 4 silent] $EDGE_CMD"
    else
        $EDGE_CMD &
    fi
fi
