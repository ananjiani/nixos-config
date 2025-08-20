#!/usr/bin/env bash

# Git Project Switcher - Open or attach to zellij session for git projects
# Finds all git repositories and allows selection via fuzzel

# Configuration
SEARCH_PATHS=(
    "$HOME"
    "$HOME/code"
    "$HOME/projects"
    "$HOME/work"
    "$HOME/dev"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to find all git repositories
find_git_repos() {
    local repos=""

    for search_path in "${SEARCH_PATHS[@]}"; do
        if [[ -d "$search_path" ]]; then
            # Use fd to find .git directories, but filter out unwanted dot directories
            while IFS= read -r git_dir; do
                # Get the parent directory (the actual project directory)
                project_dir=$(dirname "$git_dir")
                # Get just the project name
                project_name=$(basename "$project_dir")

                # Skip if project_dir is empty or just a dot
                if [[ -n "$project_dir" && "$project_dir" != "." ]]; then
                    # Check if any part of the path contains a dot directory we want to exclude
                    # Split the path and check each component
                    skip=false
                    IFS='/' read -ra PATH_PARTS <<< "$project_dir"
                    for part in "${PATH_PARTS[@]}"; do
                        # If it's a dot directory and NOT .dotfiles or .claude, skip it
                        if [[ "$part" == .* ]] && [[ "$part" != ".dotfiles" ]] && [[ "$part" != ".claude" ]]; then
                            skip=true
                            break
                        fi
                    done

                    if [[ "$skip" == false ]]; then
                        # Use directory modification time (fastest approach)
                        last_modified=$(stat -c %Y "$project_dir" 2>/dev/null || echo "0")
                        repos+="$last_modified|$project_name|$project_dir"$'\n'
                    fi
                fi
            done < <(fd -H -t d '^\.git$' "$search_path" 2>/dev/null | head -200)
        fi
    done

    # Sort by modification time (newest first), remove timestamps, and remove duplicates
    echo "$repos" | sort -t'|' -k1 -rn | cut -d'|' -f2- | awk '!seen[$0]++' | grep -v '^$'
}

# Function to get zellij session name from project path
get_session_name() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    # Replace spaces and special characters with underscores
    echo "$project_name" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Function to check if zellij session exists
session_exists() {
    local session_name="$1"
    zellij list-sessions 2>/dev/null | grep -q "^$session_name"
}

# Function to create or attach to zellij session
open_project() {
    local project_path="$1"
    local session_name=$(get_session_name "$project_path")

    # Check if directory exists
    if [[ ! -d "$project_path" ]]; then
        notify-send "Git Project Switcher" "Directory not found: $project_path" -u critical
        exit 1
    fi

    # Check if session already exists
    if session_exists "$session_name"; then
        # Attach to existing session
        echo -e "${GREEN}Attaching to existing session: $session_name${NC}"
        exec foot -e zellij attach "$session_name"
    else
        # Create new session
        echo -e "${GREEN}Creating new session: $session_name${NC}"
        exec foot -e bash -c "cd '$project_path' && zellij -s '$session_name'"
    fi
}

# Main function
main() {
    echo "Finding git repositories..."

    # Find all git repositories
    repos=$(find_git_repos)

    # Check if any repositories were found
    if [[ -z "$repos" ]]; then
        notify-send "Git Project Switcher" "No git repositories found in search paths" -u normal
        exit 0
    fi

    # Count repositories
    repo_count=$(echo "$repos" | wc -l)
    echo "Found $repo_count git repositories"

    # Format the list for fuzzel (show project name and path)
    display_list=""
    while IFS='|' read -r project_name project_path; do
        # Skip empty lines
        if [[ -n "$project_name" && -n "$project_path" ]]; then
            display_list+="$project_name ($project_path)"$'\n'
        fi
    done <<< "$repos"

    # Remove trailing newline
    display_list=${display_list%$'\n'}

    # Show selection in fuzzel
    selected=$(echo "$display_list" | fuzzel --dmenu --prompt="Open git project: " --width=60)

    # If user made a selection
    if [[ -n "$selected" ]]; then
        # Extract project path from the selection
        project_path=$(echo "$selected" | sed 's/.*(\(.*\))$/\1/')

        if [[ -n "$project_path" ]]; then
            echo "Selected project: $project_path"
            open_project "$project_path"
        else
            notify-send "Git Project Switcher" "Failed to parse selected project" -u critical
            exit 1
        fi
    fi
}

# Run main function
main "$@"
