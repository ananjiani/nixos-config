#!/bin/bash

# Launch Microsoft Edge with Outlook and Teams on weekdays only, before 5pm
# Uses Mullvad split tunneling and opens in workspace 4

# Check if today is a weekday (Monday=1, Sunday=7)
day_of_week=$(date +%u)

# Check current hour (24-hour format)
current_hour=$(date +%H)

# Only run Monday through Friday (1-5) and before 5pm (17:00)
if [ "$day_of_week" -le 5 ] && [ "$current_hour" -lt 17 ]; then
    # Launch Edge with Outlook and Teams in workspace 4 using Mullvad exclude
    hyprctl dispatch exec "[workspace 4 silent] mullvad-exclude flatpak run com.microsoft.Edge https://outlook.office365.com https://teams.microsoft.com"
fi
