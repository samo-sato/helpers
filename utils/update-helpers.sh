#!/bin/bash

# Go to helpers repo
cd /opt/helpers || exit 1

# Fetch latest changes from GitHub
git fetch origin main
git reset --hard origin/main

# Make all scripts executable
find . -type f -name "*.sh" -exec chmod +x {} \;

# List of scripts to create symlinks for
SCRIPTS=("log.sh" "notify.sh")  # <-- modify this list

# Create/update symlinks in /usr/local/bin
for f in "${SCRIPTS[@]}"; do
    if [ -f "$f" ]; then
        sudo ln -sf "$PWD/$f" /usr/local/bin/"${f%.sh}"
    fi
done
