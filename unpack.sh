#!/usr/bin/env bash

set -euo pipefail

HELP_TEXT=$(cat <<EOF
Usage: 
./unpack.sh <archive_file> <destination_dir>

Extracts an archive into the specified directory. Supports multiple formats.

Supported archive types:
  zip, tar, gz, tgz, bz2, tbz, tbz2, xz, txz

Behavior:
  - If the destination directory does not exist, the script asks whether to create it.
  - If the archive contains multiple top-level items and the destination is not empty,
    the script prompts before unpacking to avoid accidental mixing of files.
  - Extraction uses the appropriate tool based on file extension.
  - Existing files in the destination may be overwritten depending on the archive type
    (zip uses -o; tar always overwrites silently).

Examples:
  ./unpack.sh myfiles.zip /home/bob/
  ./unpack.sh backup.tar.gz /tmp/extracted/
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

archive="$1"
dest="$2"
ext="${archive##*.}"

if [[ ! -f "$archive" ]]; then
  echo "Error: archive '$archive' not found." >&2
  exit 1
fi

# --- Check destination existence ---
if [[ ! -d "$dest" ]]; then
  read -rp "Destination '$dest' does not exist. Create it? (y/n): " answer
  case "$answer" in
    [Yy]*)
      mkdir -p "$dest"
      echo "Created directory: $dest"
      ;;
    *)
      echo "Aborted: destination not created."
      exit 1
      ;;
  esac
fi

# --- Determine number of top-level items in archive ---
tmpdir="$(mktemp -d)"
case "$ext" in
  zip)
    unzip -Z1 "$archive" | awk -F/ '{print $1}' | sort -u >"$tmpdir/list"
    ;;
  tar|gz|tgz|bz2|tbz|tbz2|xz|txz)
    tar -tf "$archive" | awk -F/ '{print $1}' | sort -u >"$tmpdir/list"
    ;;
  *)
    echo "Error: unsupported file extension '$ext'." >&2
    echo "Supported: zip, tar, gz, tgz, bz2, tbz, tbz2, xz, txz"
    rm -rf "$tmpdir"
    exit 1
    ;;
esac

top_count=$(wc -l < "$tmpdir/list")
rm -rf "$tmpdir"

# --- Check if destination already contains files ---
if (( top_count > 1 )) && [[ -n "$(ls -A "$dest" 2>/dev/null || true)" ]]; then
  read -rp "Destination '$dest' already contains files. Continue unpacking? (y/n): " cont
  case "$cont" in
    [Yy]*) ;;
    *)
      echo "Aborted: existing files detected."
      exit 1
      ;;
  esac
fi

# --- Extract archive ---
case "$ext" in
  zip)
    unzip -o "$archive" -d "$dest"
    ;;
  tar)
    tar -xvf "$archive" -C "$dest"
    ;;
  gz|tgz)
    tar -xzvf "$archive" -C "$dest"
    ;;
  bz2|tbz|tbz2)
    tar -xjvf "$archive" -C "$dest"
    ;;
  xz|txz)
    tar -xJvf "$archive" -C "$dest"
    ;;
esac

echo "Unpacked '$archive' into '$dest'"

