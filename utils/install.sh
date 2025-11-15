#!/bin/bash
# install.sh - sets up helpers repo: symlinks + APT post-upgrade hook

set -e  # Exit on error

# Helpers root (one level up from this script)
HELPERS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="/var/log/helpers"
SYMLINK_SCRIPT="$HELPERS_DIR/utils/create-symlinks.sh"
HOOK_FILE="/etc/apt/apt.conf.d/99update-helpers"
HOOK_LINE="DPkg::Post-Invoke { \"$HELPERS_DIR/utils/update-helpers.sh || true\"; };"

echo "Installing helpers from $HELPERS_DIR ..."

# Check helpers directory exists
if [ ! -d "$HELPERS_DIR" ]; then
    echo "Error: $HELPERS_DIR does not exist. Clone the repo first."
    exit 1
fi

# Create/update symlinks
if [ -f "$SYMLINK_SCRIPT" ]; then
    echo "Creating symlinks for top-level scripts..."
    sudo "$SYMLINK_SCRIPT"
else
    echo "Error: Symlink script not found at $SYMLINK_SCRIPT"
    exit 1
fi

# Create log directory if it doesn't exist
echo "Creating log directory $LOG_DIR ..."
sudo mkdir -p "$LOG_DIR"

# Make log directory writable by any user
echo "Making log directory writable by any user ..."
sudo chmod 1777 "$LOG_DIR"

# Create/update APT post-upgrade hook
echo "Setting up APT post-upgrade hook..."
echo "$HOOK_LINE" | sudo tee "$HOOK_FILE" > /dev/null
echo " - Hook written to $HOOK_FILE"

echo "Installation complete. Helpers are ready and will auto-update after 'apt upgrade'."

