#!/bin/bash

set -e  # Exit on error

# Confirm with user
read -p "Are you sure you want to uninstall helpers and remove all related files? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

HELPERS_DIR="/opt/helpers"
LOG_DIR="/var/log/helpers"
SYMLINK_DIR="/usr/local/bin"
SYMLINK_SCRIPT="$HELPERS_DIR/utils/scripts/create-symlinks.sh"

echo "Uninstalling helpers ..."

# Remove symlinks for top-level .sh scripts
if [ -f "$SYMLINK_SCRIPT" ]; then
    echo "Removing symlinks for top-level scripts..."
    for f in "$HELPERS_DIR"/*.sh; do
        [ -e "$f" ] || continue
        sudo rm -f "$SYMLINK_DIR/$(basename "$f" .sh)"
        echo " - symlink removed for $(basename "$f" .sh)"
    done
fi

# Ask user if they want to remove the log directory
read -p "Do you want to remove $LOG_DIR and all its contents? [y/N]: " DELETE_LOGS
if [[ "$DELETE_LOGS" =~ ^[Yy]$ ]]; then
    echo "Removing $LOG_DIR ..."
    sudo rm -rf "$LOG_DIR"
else
    echo "Skipping removal of $LOG_DIR"
fi

# Remove the helpers repo itself
echo "Removing helpers repo ..."
sudo rm -rf "$HELPERS_DIR"

echo "Uninstallation complete."

