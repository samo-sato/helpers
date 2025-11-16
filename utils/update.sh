#!/bin/bash

# Get helpers root dir name (one level up from this script)
HELPERS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Create log bout this update
"$HELPERS_DIR/log.sh" -m "Helper update run"

# Go to helpers repo
cd "$HELPERS_DIR" || exit 1

# Fetch latest changes from GitHub and reset to match remote
git fetch origin main
git reset --hard origin/main

# Path to the symlink creation script
SYMLINK_SCRIPT="$HELPERS_DIR/utils/create-symlinks.sh"

# Run the script if it exists, otherwise exit with an error
if [[ -f "$SYMLINK_SCRIPT" ]]; then
    bash "$SYMLINK_SCRIPT"
else
    echo "Error: symlink creation script not found at $SYMLINK_SCRIPT"
    exit 1
fi
