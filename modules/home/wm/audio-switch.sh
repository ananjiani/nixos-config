#!/usr/bin/env bash

# Get list of audio sinks from wpctl
get_sinks() {
    wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -E '^\s*│.*[0-9]+\.' | while read -r line; do
        # Skip if this is the Sources line
        [[ "$line" =~ Sources: ]] && break
        
        # Check if this is the current default (has asterisk after the │)
        if [[ "$line" =~ \*[[:space:]]*[0-9]+ ]]; then
            is_default="*"
        else
            is_default=""
        fi
        
        # Extract ID - the first number sequence followed by a dot
        id=$(echo "$line" | sed -E 's/^[^0-9]*([0-9]+)\..*/\1/')
        
        # Extract name - everything between the dot and [vol:]
        name=$(echo "$line" | sed -E 's/^[^0-9]*[0-9]+\.\s*([^[]+)\[.*/\1/' | sed 's/\s*$//')
        
        # Only output if we have both ID and name
        if [ -n "$id" ] && [ -n "$name" ]; then
            echo "$id|$name|$is_default"
        fi
    done
}

# Get the list of sinks
sinks=$(get_sinks)

if [ -z "$sinks" ]; then
    exit 1
fi

# Use fuzzel to select a sink
selected=$(echo "$sinks" | while IFS='|' read -r id name is_default; do
    if [ "$is_default" = "*" ]; then
        echo "[Current] $name|$id"
    else
        echo "$name|$id"
    fi
done | fuzzel --dmenu --prompt="Select audio device: " | cut -d'|' -f2)

# Exit if no selection was made
if [ -z "$selected" ]; then
    exit 0
fi

# Switch to the selected sink
wpctl set-default "$selected"