#!/bin/bash

# Default file for adding logs into it
DEFAULT_LOG_FILE="/var/log/helpers/logs"

LOG_FILE="$DEFAULT_LOG_FILE"
MESSAGE=""
CALLER=""

HELP_TEXT=$(cat <<'EOF'
Usage:
log.sh -m "Message text" [-p "Log prefix"] [-f "Log file path"]

Options:
  -m   Message text (required)
  -p   Log prefix (optional; appears in brackets before the message)
  -f   Log file path (optional; default: /var/log/helpers/logs)
  -h   Show this help message

Notes:
  - If you specify a custom log file with -f, ensure the user running the script
    has write permissions to the target directory and file.
  - The script will automatically create the directory path if needed.

Log format:
  {timestamp} [{log_prefix}] {message}
  If no prefix is provided, the brackets are omitted.

Timestamp format:
  YYYY-MM-DD HH:MM

Examples:
  ./log.sh -m "Disk almost full!"
  ./log.sh -m "Service stopped!" -p "MonitoringService"
  ./log.sh -m "Backup completed" -f "/var/log/backup/backup.log"

Default log file location:
  /var/log/helpers/logs
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
while getopts "m:pf:h" opt; do
  case $opt in
    m) MESSAGE="$OPTARG" ;;
    p) USE_CALLER_NAME=true ;;
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
if [[ -n "$CALLER" ]]; then
    LOG_LINE="$TIMESTAMP [$CALLER] $MESSAGE"
else
    LOG_LINE="$TIMESTAMP $MESSAGE"
fi

# Output to file and echo for user feedback
echo "$LOG_LINE" | tee -a "$LOG_FILE" > /dev/null
