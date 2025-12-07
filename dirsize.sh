#!/usr/bin/env bash

set -euo pipefail

HELP_TEXT=$(cat <<'EOF'
Usage:
  ./dirsize.sh [directory_path]

Print human-readable sizes of directories and files (first level) in the specified location, sorted by size (largest first).

Examples:
  ./dirsize.sh              # Check current directory
  ./dirsize.sh /var/log     # Check specific directory

Notes:
  - If [directory_path] is omitted, the current directory is used.
  - Requires read permissions for the target directory.
  - Displays sizes for both files and subdirectories.
EOF
)

# Show help text
show_help() {
  echo "$HELP_TEXT"
}

# --- Show help only when help flag is explicitly used ---
# We use ${1:-} to handle the case where $1 is undefined (empty) without crashing
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# Use the provided argument, or default to current directory "."
target="${1:-.}"

if [[ ! -d "$target" ]]; then
  echo "Error: directory '$target' does not exist." >&2
  exit 1
fi

# --- Calculate sizes and sort ---
# du -ah: All files, Human readable
# --max-depth=1: First level only
# sort -hr: Human numeric sort (understands K, M, G), Reverse (biggest first)
du -ah --max-depth=1 "$target" | sort -hr
