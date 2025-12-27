#!/bin/bash

# Default file for adding logs into it
DEFAULT_LOG_FILE="/var/log/helpers/logs"

LOG_FILE="$DEFAULT_LOG_FILE"
MESSAGE=""

# Default to parent script name immediately
CALLER=$(ps -p $PPID -o args= | awk '{print $2}')
[[ -z "$CALLER" ]] && CALLER=$(ps -p $PPID -o comm=)

HELP_TEXT=$(cat <<'EOF'
Usage:
log.sh -m "Message text" [-p "Custom prefix"] [-f "Log file path"]

Options:
  -m   Message text (required)
  -p   Custom prefix (optional; defaults to the calling script's path)
  -f   Log file path (optional; default: /var/log/helpers/logs)
  -h   Show this help message

Log format:
  {timestamp} [{prefix}] {message}
  Note: The brackets and prefix (script name) are now included by default.

Examples:
  ./log.sh -m "Done"             # Result: [2025-12-12 15:47] [/opt/test.sh] Done
  ./log.sh -m "Done" -p "Cron"   # Result: [2025-12-12 15:47] [Cron] Done
EOF
)

show_help() {
    echo "$HELP_TEXT"
}

# If no args provided, show help
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

# Parse options
while getopts "m:p:f:h" opt; do
  case $opt in
    m) MESSAGE="$OPTARG" ;;
    p) CALLER="$OPTARG" ;; # Overwrites the default script name with custom text
    f) LOG_FILE="$OPTARG" ;;
    h) show_help; exit 0 ;;
    *) show_help; exit 1 ;;
  esac
done

# Handle optional -p flag:
# 1. If a value follows -p (and isn't another flag), use it as the prefix.
# 2. If -p is standalone, auto-detect the calling script's path via Parent Process ID ($PPID).
if [ "$USE_CALLER_NAME" = true ]; then
    # Peek at the next argument in the stack
    NEXT_ARG="${!OPTIND}"

    # If the next arg exists and doesn't start with "-", it's a custom prefix
    if [[ -n "$NEXT_ARG" && "$NEXT_ARG" != -* ]]; then
        CALLER="$NEXT_ARG"
        OPTIND=$((OPTIND + 1)) # Move pointer forward
    else
        # Otherwise, find the command name of the Parent Process ID (PPID)
        # -o args= gets the full command line of the caller
        CALLER=$(ps -p $PPID -o args= | awk '{print $2}')

        # Fallback to process name if path isn't available
        [[ -z "$CALLER" ]] && CALLER=$(ps -p $PPID -o comm=)
    fi
fi

# Validate message
if [[ -z "$MESSAGE" ]]; then
    echo "Error: Message (-m) is required." >&2
    show_help
    exit 1
fi

# Ensure log file exists
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" 2>/dev/null || {
    echo "Error: Cannot write to $LOG_FILE" >&2
    exit 1
}

# Build log line
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
LOG_LINE="$TIMESTAMP [$CALLER] $MESSAGE"

# Output to file and echo for user feedback
echo "$LOG_LINE" | tee -a "$LOG_FILE" > /dev/null
