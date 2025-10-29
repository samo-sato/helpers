#!/bin/bash

HELPERS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYMLINK_DIR="/usr/local/bin"

echo "Creating/updating symlinks for top-level scripts in $HELPERS_DIR ..."

# Loop over top-level .sh files
for f in "$HELPERS_DIR"/*.sh; do
    [ -e "$f" ] || continue
    sudo ln -sf "$f" "$SYMLINK_DIR/$(basename "$f" .sh)"
    echo " - symlink created for $(basename "$f" .sh)"
done

