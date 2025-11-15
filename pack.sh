#!/usr/bin/env bash

set -euo pipefail

HELP_TEXT=$(cat <<'EOF'
Usage:
./pack.sh <source_path> <destination_file>

Compress files or directories into various archive formats based on the destination filename extension.

Supported formats:
  zip       → zip archive
  tar       → uncompressed tar
  gz, tgz   → tar.gz
  bz2, tbz  → tar.bz2
  xz, txz   → tar.xz

Examples:
  pack /var/log mylogs.zip
  pack /home/bob/project project.tar.gz
  pack ./folder archive.txz

Notes:
  - <source_path> must exist.
  - The compression method is chosen automatically using the file extension.
  - The pack.sh script must be executable: chmod +x pack.sh
EOF
)

# Show help text
show_help() {
    echo "$HELP_TEXT"
}

# --- Show help when no args or when help flag is used ---
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

src="$1"
dest="$2"
ext="${dest##*.}"

if [[ ! -e "$src" ]]; then
  echo "Error: source '$src' does not exist." >&2
  exit 1
fi

# --- Choose compression method based on extension ---
case "$ext" in
  zip)
    zip -r "$dest" "$src"
    ;;
  tar)
    tar -cvf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
    ;;
  gz|tgz)
    tar -czvf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
    ;;
  bz2|tbz|tbz2)
    tar -cjvf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
    ;;
  xz|txz)
    tar -cJvf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
    ;;
  *)
    echo "Error: unsupported file extension '$ext'." >&2
    echo "Supported: zip, tar, gz, tgz, bz2, tbz, tbz2, xz, txz"
    exit 1
    ;;
esac

echo "Packed '$src' into '$dest'"

