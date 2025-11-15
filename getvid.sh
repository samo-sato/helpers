#!/usr/bin/env bash
# Usage: getvid.sh <url> [destination] [--lowres] [--cookies=/path/to/cookies.txt]
# Example: getvid.sh "https://youtu.be/abc123" "/home/bob/videos" --lowres --cookies=/path/to/cookies.txt

set -euo pipefail
MAX_NAME_LEN=140

# --- Help message ---

HELP_TEXT=$(cat <<EOF
Usage:
./getvid.sh <url> [destination] [--lowres] [--cookies=/path/to/cookies.txt]

Downloads a YouTube (or other supported) video using yt-dlp.

Options:
  -h, --help               Show this help message and exit
  --lowres                 Download the lowest resolution video (with audio)
  --cookies=<path>         Use a cookies file for authentication

Behavior:
  - If destination is not provided, saves to the home directory (~)
  - Filenames are sanitized and limited to ${MAX_NAME_LEN} characters
  - If a file with the same name exists, the script aborts (no overwrite)
EOF
)

# Show help text
show_help() {
    echo "$HELP_TEXT"
}

# --- Check dependencies ---
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "Error: yt-dlp is not installed or not in PATH."
  exit 1
fi

# --- Show help when no args or when help flag is used ---
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

url="$1"
dest="$HOME"
quality="bestvideo+bestaudio/best"
cookies_arg=""

# Parse optional arguments
for arg in "${@:2}"; do
    if [[ "$arg" == "--lowres" ]]; then
        # Use the lowest resolution video and audio combination
        quality="worstvideo+worstaudio/worst"
    elif [[ "$arg" == --cookies=* ]]; then
        cookies_arg="$arg"
    else
        dest="$arg"
    fi
done

# --- Ensure destination exists ---
if [[ ! -d "$dest" ]]; then
  echo "Error: destination directory '$dest' does not exist."
  exit 1
fi

# --- Get video title using yt-dlp ---
title="$(yt-dlp --get-title "$url" 2>/dev/null || true)"
if [[ -z "$title" ]]; then
  # fallback: use sanitized URL
  title="$url"
fi

# --- Sanitize and normalize filename ---
sanitized="$(echo "$title" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || echo "$title")"
sanitized="${sanitized// /_}"                                # Replace spaces with underscores
sanitized="$(echo "$sanitized" | tr -cd 'A-Za-z0-9._-')"    # Keep only allowed characters
sanitized="${sanitized##.}"                                  # Remove leading dots
sanitized="$(echo "$sanitized" | cut -c1-${MAX_NAME_LEN})"  # Trim to max allowed length

# --- Get file extension from yt-dlp ---
ext="$(yt-dlp --print filename -o '%(ext)s' "$url" 2>/dev/null || echo 'mp4')"
filename="${sanitized}.${ext}"

# --- Check for existing file ---
if [[ -e "$dest/$filename" ]]; then
  echo "Error: file '$dest/$filename' already exists. Aborting."
  exit 1
fi

# --- Download video with optional cookies and quality ---
yt-dlp $cookies_arg -f "$quality" -o "$dest/$filename" "$url"

echo "Downloaded '$filename' to '$dest'"

