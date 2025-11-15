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
while getopts "m:p:f:h" opt; do
  case $opt in
    m) MESSAGE="$OPTARG" ;;
    p) CALLER="$OPTARG" ;;
    f) LOG_FILE="$OPTARG" ;;
    h) show_help; exit 0 ;;
    *) show_help; exit 1 ;;
  esac
done


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
echo "$LOG_LINE" >> "$LOG_FILE"
