#!/usr/bin/env bash

# Get all windows with their workspace and class information
windows_json=$(hyprctl clients -j)

# Parse and format the window list
window_list=""
while IFS= read -r window; do
    # Extract window properties
    address=$(echo "$window" | jq -r '.address')
    class=$(echo "$window" | jq -r '.class // "Unknown"')
    title=$(echo "$window" | jq -r '.title // "Untitled"')
    workspace=$(echo "$window" | jq -r '.workspace.id // "?"')
    workspace_name=$(echo "$window" | jq -r '.workspace.name // "?"')

    # Skip empty entries
    if [[ -n "$address" && "$address" != "null" ]]; then
        # Format: [Workspace] Class: Title
        entry="[$workspace_name] $class: $title"
        window_list+="$address|$entry"$'\n'
    fi
done < <(echo "$windows_json" | jq -c '.[]')

# Remove trailing newline
window_list=${window_list%$'\n'}

# If no windows found, exit
if [[ -z "$window_list" ]]; then
    notify-send "Window Switcher" "No windows found"
    exit 0
fi

# Show window list in fuzzel and get selection
selected=$(echo "$window_list" | while IFS='|' read -r addr entry; do
    echo "$entry"
done | fuzzel --dmenu --prompt="Switch to window: ")

# If user selected a window, focus it
if [[ -n "$selected" ]]; then
    # Find the address for the selected entry
    address=$(echo "$window_list" | while IFS='|' read -r addr entry; do
        if [[ "$entry" == "$selected" ]]; then
            echo "$addr"
            break
        fi
    done)

    if [[ -n "$address" ]]; then
        hyprctl dispatch focuswindow "address:$address"
    fi
fi
