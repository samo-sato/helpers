#!/bin/bash

# Go to helpers repo
cd "$HELPERS_DIR/helpers" || exit 1

# Fetch latest changes from GitHub and reset to match remote
git fetch origin main
git reset --hard origin/main

# Call the symlink creation script
if [ -f "$HELPERS_DIR/utils/create_symlinks.sh" ]; then
    bash "$HELPERS_DIR/utils/create_symlinks.sh"
else
    echo "Error: symlink creation script not found at $HELPERS_DIR/utils/create_symlinks.sh"
    exit 1
fi

