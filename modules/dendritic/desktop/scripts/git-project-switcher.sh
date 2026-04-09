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

# Cache configuration
CACHE_DIR="$HOME/.cache/git-project-switcher"
CACHE_FILE="$CACHE_DIR/repos.cache"
CACHE_TTL=300  # 5 minutes in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
FORCE_REFRESH=false
USE_CACHE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --refresh)
            FORCE_REFRESH=true
            shift
            ;;
        --no-cache)
            USE_CACHE=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--refresh] [--no-cache]"
            exit 1
            ;;
    esac
done

# Cache management functions
create_cache_dir() {
    if [[ ! -d "$CACHE_DIR" ]]; then
        mkdir -p "$CACHE_DIR"
    fi
}

is_cache_valid() {
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    local cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local age=$((current_time - cache_time))

    [[ $age -lt $CACHE_TTL ]]
}

read_cache() {
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
    fi
}

write_cache() {
    local repos="$1"
    create_cache_dir
    echo "$repos" > "$CACHE_FILE"
}

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

# Function to find all git repositories (optimized version with mod time)
find_git_repos_fresh() {
    local all_repos=""
    local pids=()
    local temp_files=()

    # Create temporary files for parallel processing
    for i in "${!SEARCH_PATHS[@]}"; do
        temp_files[i]=$(mktemp)
    done

    # Start parallel fd processes for each search path
    for i in "${!SEARCH_PATHS[@]}"; do
        search_path="${SEARCH_PATHS[i]}"
        temp_file="${temp_files[i]}"

        if [[ -d "$search_path" ]]; then
            (
                # Use fd with better exclusion patterns
                fd -H -t d '^\.git$' "$search_path" \
                    --exclude '*/.cache/*' \
                    --exclude '*/.npm/*' \
                    --exclude '*/.yarn/*' \
                    --exclude '*/node_modules/*' \
                    --exclude '*/.vscode/*' \
                    --exclude '*/.idea/*' \
                    2>/dev/null | \
                while IFS= read -r git_dir; do
                    project_dir=$(dirname "$git_dir")
                    project_name=$(basename "$project_dir")

                    # Check if any part of the path contains a dot directory we want to exclude
                    skip=false
                    IFS='/' read -ra PATH_PARTS <<< "$project_dir"
                    for part in "${PATH_PARTS[@]}"; do
                        # If it's a dot directory and NOT .dotfiles or .claude, skip it
                        if [[ "$part" == .* ]] && [[ "$part" != ".dotfiles" ]] && [[ "$part" != ".claude" ]]; then
                            skip=true
                            break
                        fi
                    done

                    if [[ "$skip" == false && -n "$project_dir" && "$project_dir" != "." ]]; then
                        # Keep modification time for sorting
                        last_modified=$(stat -c %Y "$project_dir" 2>/dev/null || echo "0")
                        echo "$last_modified|$project_name|$project_dir"
                    fi
                done > "$temp_file"
            ) &
            pids[i]=$!
        else
            # Create empty temp file for non-existent paths
            touch "${temp_files[i]}"
        fi
    done

    # Wait for all background processes and collect results
    for i in "${!pids[@]}"; do
        wait "${pids[i]}"
        if [[ -f "${temp_files[i]}" ]]; then
            all_repos+=$(cat "${temp_files[i]}")$'\n'
        fi
        rm -f "${temp_files[i]}"
    done

    # Sort by modification time (newest first), remove timestamps, remove duplicates, limit to 200
    echo "$all_repos" | grep -v '^$' | sort -t'|' -k1 -rn | cut -d'|' -f2- | awk '!seen[$0]++' | head -200
}

# Background cache refresh function
refresh_cache_background() {
    # Run in background to avoid blocking UI
    (
        local repos
        if command -v mktemp >/dev/null 2>&1; then
            repos=$(find_git_repos_fresh)
        else
            repos=$(find_git_repos)
        fi
        write_cache "$repos"
    ) &
}

# Function to get repositories (with caching and background refresh)
get_git_repos() {
    # Check if cache exists and is valid
    if [[ "$USE_CACHE" == true && "$FORCE_REFRESH" == false ]] && is_cache_valid; then
        read_cache
        return 0
    fi

    # Check if cache exists but is stale (between 5-15 minutes old)
    if [[ "$USE_CACHE" == true && "$FORCE_REFRESH" == false && -f "$CACHE_FILE" ]]; then
        local cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local age=$((current_time - cache_time))

        # If cache is stale but not too old (5-15 minutes), use it but refresh in background
        if [[ $age -ge $CACHE_TTL && $age -lt $((CACHE_TTL * 3)) ]]; then
            # Start background refresh
            refresh_cache_background
            # Return stale cache immediately
            read_cache
            return 0
        fi
    fi

    # Refresh repositories synchronously (cache is too old or doesn't exist)
    local repos
    if command -v mktemp >/dev/null 2>&1; then
        repos=$(find_git_repos_fresh)
    else
        repos=$(find_git_repos)
    fi

    # Write to cache if caching is enabled
    if [[ "$USE_CACHE" == true ]]; then
        write_cache "$repos"
    fi

    echo "$repos"
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
    echo "DEBUG: Checking if session exists: $session_name" >&2
    local sessions=$(zellij list-sessions 2>/dev/null)
    echo "DEBUG: Available sessions:" >&2
    echo "$sessions" >&2

    # Check if session name exists at the start of a line (followed by space)
    if echo "$sessions" | grep -q "^${session_name} "; then
        echo "DEBUG: Session '$session_name' found!" >&2
        return 0
    else
        echo "DEBUG: Session '$session_name' not found!" >&2
        return 1
    fi
}

# Function to create or attach to zellij session
open_project() {
    local project_path="$1"
    local session_name=$(get_session_name "$project_path")

    echo "DEBUG: Project path: $project_path" >&2
    echo "DEBUG: Session name: $session_name" >&2

    # Check if directory exists
    if [[ ! -d "$project_path" ]]; then
        notify-send "Git Project Switcher" "Directory not found: $project_path" -u critical
        exit 1
    fi

    # Check if session already exists
    if session_exists "$session_name"; then
        # Attach to existing session
        echo -e "${GREEN}Attaching to existing session: $session_name${NC}"
        echo "DEBUG: Running command: foot -e bash -c \"cd '$project_path' && zellij attach '$session_name'\"" >&2
        # Log to a file for debugging
        echo "$(date): Attempting to attach to session $session_name at path $project_path" >> /tmp/git-project-switcher.log
        exec foot -e bash -c "cd '$project_path' && echo 'DEBUG: In foot terminal, pwd:' && pwd && echo 'DEBUG: Attempting zellij attach $session_name' && zellij attach '$session_name' || (echo 'DEBUG: Attach failed with exit code:' \$? && sleep 5)"
    else
        # Create new session
        echo -e "${GREEN}Creating new session: $session_name${NC}"
        echo "DEBUG: Running command: foot -e bash -c \"cd '$project_path' && zellij attach -c '$session_name'\"" >&2
        # Log to a file for debugging
        echo "$(date): Creating new session $session_name at path $project_path" >> /tmp/git-project-switcher.log
        # Use 'attach -c' which creates if not exists, or attaches if it does
        exec foot -e bash -c "cd '$project_path' && echo 'DEBUG: In foot terminal, pwd:' && pwd && echo 'DEBUG: Creating/attaching zellij session $session_name' && zellij attach -c '$session_name'"
    fi
}

# Main function
main() {
    # Show status message based on caching
    if [[ "$USE_CACHE" == true && "$FORCE_REFRESH" == false ]] && is_cache_valid; then
        echo "Loading git repositories from cache..."
    else
        echo "Finding git repositories..."
    fi

    # Get all git repositories (with caching)
    repos=$(get_git_repos)

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
