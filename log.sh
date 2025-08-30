#!/bin/bash

# Logging function to log timestamped messages to file

# Usage:
# log.sh "{message}" "{optional calling source name}"

# Logs format:
# {timestamp} [{calling_script}] {message}
# If calling source is not provided, brackets are omitted

# Example call from terminal and resulted line in log file
# /usr/local/bin/sysutils/log.sh "Disk almost full!" "$0"
# 2025-08-30 21:33 [-bash] Disk almost full!

LOG_FILE="/usr/local/bin/sysutils/logs"

MESSAGE="$1"
CALLER="$2"  # Optional

if [[ -z "$MESSAGE" ]]; then
    echo "Usage: $0 \"Main message\" [\"Optional calling script name\"]" >&2
    exit 1
fi

TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

# Only include brackets if CALLER is non-empty
if [[ -n "$CALLER" ]]; then
    LOG_LINE="$TIMESTAMP [$CALLER] $MESSAGE"
else
    LOG_LINE="$TIMESTAMP $MESSAGE"
fi

echo "$LOG_LINE" >> "$LOG_FILE"
