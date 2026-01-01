#!/usr/bin/env bash
# Usage: getvid.sh <url> [destination] [--lowres] [--cookies=/path/to/cookies.txt]

set -euo pipefail
MAX_NAME_LEN=140

# --- Check dependencies ---
for cmd in yt-dlp iconv tr; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $(basename "$0") <url> [destination] [--lowres] [--cookies=/path/to/cookies.txt]"
    exit 0
fi

# --- Parse Arguments ---
url="$1"
dest="$PWD"
quality="bestvideo+bestaudio/best"
cookies_arg=""

shift
for arg in "$@"; do
    case "$arg" in
        --lowres) quality="worstvideo+worstaudio/worst" ;;
        --cookies=*) cookies_arg="$arg" ;;
        *) [[ -n "$arg" && ! "$arg" =~ ^- ]] && dest="$arg" ;;
    esac
done

[[ ! -d "$dest" ]] && { echo "Error: destination '$dest' not found."; exit 1; }

echo "Fetching metadata..."

# --- Step 1: Get Title and Extension ---
# Use a unique separator to split title and extension safely
raw_output=$(yt-dlp $cookies_arg --get-title --print "EXT:%(ext)s" "$url")

# Separate the multi-line output (Title is usually first line, EXT: is the last)
raw_title=$(echo "$raw_output" | sed '/^EXT:/d' | head -n 1)
ext=$(echo "$raw_output" | grep "^EXT:" | cut -d: -f2- | head -n 1)

# Default extension if detection fails
ext="${ext:-mp4}"

# --- Step 2: Strict Sanitization Pipeline ---

# 1. Transliterate to ASCII (cim, na, trhoch...)
clean_title=$(echo "$raw_title" | iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null || echo "$raw_title")

# 2. Manual replacements (dots, pluses to hyphens; spaces to underscores)
clean_title="${clean_title//./-}"
clean_title="${clean_title//+/-}"
clean_title="${clean_title// /_}"
clean_title="${clean_title//\'/}"
clean_title="${clean_title//\"/}"

# 3. Strip everything except A-Z, a-z, 0-9, _, and -
clean_title=$(echo "$clean_title" | tr -cd 'A-Za-z0-9._-')

# 4. Collapse multiple separators (the fix for your tr error)
clean_title=$(echo "$clean_title" | tr -s '-' | tr -s '_')

# 5. Trim to length
max_title_len=$((MAX_NAME_LEN - ${#ext} - 1))
clean_title="${clean_title:0:$max_title_len}"
clean_title="${clean_title%[-_]}" # Remove trailing hyphen/underscore

final_filename="${clean_title}.${ext}"

echo "Target filename: $final_filename"

# --- Step 3: Check for existing file ---
if [[ -e "$dest/$final_filename" ]]; then
    echo "Error: file '$dest/$final_filename' already exists. Aborting."
    exit 1
fi

# --- Step 4: Download ---
yt-dlp $cookies_arg -f "$quality" -o "$dest/$final_filename" "$url"

echo "Done: $final_filename"
