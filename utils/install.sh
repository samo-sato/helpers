#!/bin/bash
set -e # Exit on error

# === 1. Check for sudo privileges ===
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run with sudo (as root)." >&2
    exit 1
fi

# === 2. Helpers root (one level up from this script) ===
HELPERS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="/var/log/helpers"
SYMLINK_SCRIPT="$HELPERS_DIR/utils/create-symlinks.sh"
UPDATER_SCRIPT="$HELPERS_DIR/utils/update.sh"

echo "Installing helpers from $HELPERS_DIR ..."

# Check helpers directory exists
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

# === 3. Ask user about systemd service (auto-update on boot) ===
echo
echo "Would you like to install a systemd service that automatically checks for updates"
echo "on every system boot? This will run '$UPDATER_SCRIPT' and auto-answer 'y' if an update is available."
echo
read -r -p "Install auto-update on boot? (y/N): " answer
case "$answer" in
    [Yy]* )
        echo "Creating systemd service for auto-update on boot..."

        cat > /etc/systemd/system/helpers-auto-update.service <<EOF
[Unit]
Description=Auto-update helpers on boot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo y | $UPDATER_SCRIPT'
RemainAfterExit=yes
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable helpers-auto-update.service

        echo "Systemd service installed and enabled."
        ;;
    * )
        echo "Auto-update on boot skipped."
        ;;
esac

echo "Installation complete"
