#!/usr/bin/env bash

set -euo pipefail

HELP_TEXT=$(cat <<'EOF'
Usage:
  ./search.sh [flags] <pattern> [directory_path]

Search for a text pattern in filenames/directory names or file contents.

Arguments:
  <pattern>         : The text to search for (e.g., "report"). (Required)
  [directory_path]  : The path to start searching from. (Default: current directory ".")

Flags:
  -content          : Also search within the *content* of files.
  -case             : Makes the search case-sensitive (default is case-insensitive).
  -h, --help        : Show this help text.

Examples:
  ./search.sh "api-key" /etc/
  ./search.sh -content "secret"
  ./search.sh -content -case "ERROR" /var/log/

Notes:
  - Searches filenames and directory names by default (case-insensitive).
  - Content searches use 'grep' and highlight matches.
  - Includes hidden files and directories.
EOF
)

# Initialize variables and flags
CONTENT_SEARCH=0
CASE_SENSITIVE=0

# Show help text
show_help() {
  echo "$HELP_TEXT"
}

# --- Show help when help flag is explicitly used ---
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# --- Argument Parsing Loop (Handles flags first) ---
# Loop through arguments until no flags are found
while [[ $# -gt 0 ]]; do
    case "$1" in
        -content)
            CONTENT_SEARCH=1
            shift
            ;;
        -case)
            CASE_SENSITIVE=1
            shift
            ;;
        -h|--help) # Already handled, but added for completeness
            show_help
            exit 0
            ;;
        *)
            # If the argument is not a known flag, stop parsing flags
            break
            ;;
    esac
done

# --- Process Positional Arguments ---
if [[ $# -eq 0 ]]; then
    echo "Error: Search pattern required." >&2
    show_help
    exit 1
fi

pattern="$1"
target="${2:-.}"

if [[ ! -d "$target" ]]; then
    echo "Error: target path '$target' is not a directory or does not exist." >&2
    exit 1
fi

# --- Define Search Options ---
FIND_OPTS="-iname" # Default: case-insensitive name search
GREP_OPTS="-r"     # Default: recursive

if [[ "$CASE_SENSITIVE" -eq 1 ]]; then
    FIND_OPTS="-name"
    # Grep is case-sensitive by default, so we don't add -i
else
    GREP_OPTS="-ri" # Recursive, case-insensitive
fi

echo "🔎 Searching for '$pattern' in '$target'..."

# --- Core Logic ---

if [[ "$CONTENT_SEARCH" -eq 1 ]]; then
    # Content Search (grep)
    # -n: Show line number
    # --color=always: Highlight matches in the terminal
    # Uses $GREP_OPTS (-r or -ri)
    grep -n $GREP_OPTS --color=always "$pattern" "$target" 2>/dev/null || true
    # We use '|| true' and '2>/dev/null' to prevent 'set -e' from failing the script
    # if grep finds no matches or encounters permission denied errors (common behavior).
else
    # Filename/Directory Search (find)
    # Uses $FIND_OPTS (-name or -iname)
    find "$target" $FIND_OPTS "*$pattern*"
fi
