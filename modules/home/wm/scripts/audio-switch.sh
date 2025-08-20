#!/usr/bin/env bash

# Get list of audio sinks from wpctl and format for fuzzel
wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -E '^\s*│.*[0-9]+\.' | while read -r line; do
    # Extract sink ID and name
    id=$(echo "$line" | sed -E 's/^[^0-9]*([0-9]+)\..*/\1/')
    name=$(echo "$line" | sed -E 's/^[^0-9]*[0-9]+\.\s*([^[]+)\[.*/\1/' | sed 's/\s*$//')

    # Mark current default sink
    if [[ "$line" =~ \*[[:space:]]*[0-9]+ ]]; then
        echo "[Current] $name|$id"
    else
        echo "$name|$id"
    fi
done | fuzzel --dmenu --prompt="Select audio device: " | cut -d'|' -f2 | xargs -r wpctl set-default
