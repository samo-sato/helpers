#!/bin/bash

echo "Following helper tools are available:"

# List all .sh files / helpers (top-level only) without extension
for f in /opt/helpers/*.sh; do
    [ -e "$f" ] || continue   # Skip if no .sh files exist
    basename "$f" .sh
done
