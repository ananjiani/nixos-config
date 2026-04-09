#!/usr/bin/env bash

# Work Project Switcher - Open or attach to zellij session for work projects
# Searches only in ~/Documents/projects/work/ and allows creating new projects
# Opens projects in workspace 6

# Configuration
WORK_DIR="$HOME/Documents/projects/work"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to find all git repositories in work directory
find_work_git_repos() {
    local repos=""

    if [[ -d "$WORK_DIR" ]]; then
        # Use fd to find .git directories in work directory only
        while IFS= read -r git_dir; do
            # Get the parent directory (the actual project directory)
            project_dir=$(dirname "$git_dir")
            # Get relative path from work directory
            relative_path=${project_dir#$WORK_DIR/}

            # Skip the work directory itself if it's a git repo
            if [[ "$project_dir" == "$WORK_DIR" ]]; then
                continue
            fi

            # Use directory modification time
            last_modified=$(stat -c %Y "$project_dir" 2>/dev/null || echo "0")
            repos+="$last_modified|$relative_path|$project_dir"$'\n'
        done < <(fd -H -t d '^\.git$' "$WORK_DIR" 2>/dev/null | head -200)
    fi

    # Sort by modification time (newest first) and remove duplicates
    echo "$repos" | sort -t'|' -k1 -rn | cut -d'|' -f2- | awk '!seen[$0]++' | grep -v '^$'
}

# Function to get zellij session name from project path
get_session_name() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    # Replace spaces and special characters with underscores
    echo "work_$project_name" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Function to check if zellij session exists
session_exists() {
    local session_name="$1"
    zellij list-sessions 2>/dev/null | grep -q "^$session_name"
}

# Function to create or attach to zellij session in workspace 6
open_project() {
    local project_path="$1"
    local session_name=$(get_session_name "$project_path")

    # Check if directory exists
    if [[ ! -d "$project_path" ]]; then
        notify-send "Work Project Switcher" "Directory not found: $project_path" -u critical
        exit 1
    fi

    # Check if session already exists
    if session_exists "$session_name"; then
        # Attach to existing session in workspace 6
        echo -e "${GREEN}Attaching to existing session: $session_name${NC}"
        hyprctl dispatch exec "[workspace 6 silent] foot -e zellij attach '$session_name'"
    else
        # Create new session in workspace 6
        echo -e "${GREEN}Creating new session: $session_name${NC}"
        hyprctl dispatch exec "[workspace 6 silent] foot -e bash -c \"cd '$project_path' && zellij -s '$session_name'\""
    fi
}

# Function to create a new work project
create_new_project() {
    # Prompt for project name (can include subdirectories like "client/project-name")
    project_name=$(echo "" | fuzzel --dmenu --prompt="Project name (e.g., 'my-project' or 'client/my-project'): " --width=50)

    # Check if user cancelled
    if [[ -z "$project_name" ]]; then
        notify-send "Work Project Switcher" "Project creation cancelled" -u normal
        exit 0
    fi

    # Sanitize the project name (keep slashes for subdirectories)
    project_name=$(echo "$project_name" | sed 's/[^a-zA-Z0-9._\/-]/-/g')

    # Full path to the new project
    project_path="$WORK_DIR/$project_name"

    # Check if project already exists
    if [[ -d "$project_path" ]]; then
        notify-send "Work Project Switcher" "Project already exists: $project_name" -u critical
        exit 1
    fi

    # Create the project directory
    mkdir -p "$project_path"

    # Initialize git repository
    cd "$project_path"
    git init

    # Create initial README.md
    cat > README.md << EOF
# $(basename "$project_name")

Work project created on $(date +"%Y-%m-%d")

## Description

TODO: Add project description

## Setup

TODO: Add setup instructions

## Notes

TODO: Add any relevant notes
EOF

    # Create initial commit
    git add README.md
    git commit -m "Initial commit: Create work project $(basename "$project_name")"

    # Notify user
    notify-send "Work Project Switcher" "Created new project: $project_name" -u normal

    # Open the new project
    open_project "$project_path"
}

# Main function
main() {
    echo "Finding work git repositories..."

    # Find all git repositories in work directory
    repos=$(find_work_git_repos)

    # Format the list for fuzzel (show relative path from work directory)
    display_list="✨ Create New Work Project"$'\n'

    if [[ -n "$repos" ]]; then
        while IFS='|' read -r relative_path project_path; do
            # Skip empty lines
            if [[ -n "$relative_path" && -n "$project_path" ]]; then
                display_list+="📁 $relative_path"$'\n'
            fi
        done <<< "$repos"
    fi

    # Remove trailing newline
    display_list=${display_list%$'\n'}

    # Count repositories (excluding the create new option)
    if [[ -n "$repos" ]]; then
        repo_count=$(echo "$repos" | wc -l)
        echo "Found $repo_count work git repositories"
    else
        echo "No existing work git repositories found"
    fi

    # Show selection in fuzzel
    selected=$(echo "$display_list" | fuzzel --dmenu --prompt="Work project: " --width=60)

    # If user made a selection
    if [[ -n "$selected" ]]; then
        if [[ "$selected" == "✨ Create New Work Project" ]]; then
            # Create a new project
            create_new_project
        else
            # Extract relative path from the selection (remove the 📁 prefix)
            relative_path=${selected#📁 }
            project_path="$WORK_DIR/$relative_path"

            if [[ -n "$project_path" && -d "$project_path" ]]; then
                echo "Selected project: $project_path"
                open_project "$project_path"
            else
                notify-send "Work Project Switcher" "Failed to parse selected project" -u critical
                exit 1
            fi
        fi
    fi
}

# Run main function
main "$@"
