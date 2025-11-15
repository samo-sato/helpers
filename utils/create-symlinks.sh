#!/bin/bash

HELPERS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYMLINK_DIR="/usr/local/bin"

echo "Creating/updating symlinks for top-level scripts in $HELPERS_DIR ..."

# Loop over top-level .sh files
for f in "$HELPERS_DIR"/*.sh; do
    [ -e "$f" ] || continue

    name="$(basename "$f" .sh)"
    target="$SYMLINK_DIR/$name"

    # Check for existing command or file at target
    if command -v "$name" >/dev/null 2>&1 || [ -e "$target" ]; then
        echo "Skipping '$name': a command or file with this name already exists."
        continue
    fi

    # Create symlink
    sudo ln -sf "$f" "$target"
    echo "Symlink created for '$name'"
done

