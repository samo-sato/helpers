#!/bin/bash
set -e # Exit on error

# Check for sudo privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo (as root)." >&2
    exit 1
fi

# Get helpers root dir name (one level up from this script)
HELPERS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="/var/log/helpers"
SYMLINK_SCRIPT="$HELPERS_DIR/utils/create-symlinks.sh"
UPDATER_SCRIPT="$HELPERS_DIR/utils/update.sh"

echo "Installing helpers from $HELPERS_DIR ..."

# Check if helpers directory exists
if [ ! -d "$HELPERS_DIR" ]; then
    echo "Error: $HELPERS_DIR does not exist. Clone the repo first."
    exit 1
fi

# Create/update symlinks
if [ -f "$SYMLINK_SCRIPT" ]; then
    echo "Creating symlinks for top-level scripts..."
    "$SYMLINK_SCRIPT"
else
    echo "Error: Symlink script not found at $SYMLINK_SCRIPT"
    exit 1
fi

# Create log directory if it doesn't exist
echo "Creating log directory $LOG_DIR ..."
mkdir -p "$LOG_DIR"

# Make log directory writable by any user
echo "Making log directory writable by any user ..."
chmod 1777 "$LOG_DIR"

echo "Installation complete"
