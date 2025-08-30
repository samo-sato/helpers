#!/bin/bash

# Usage:
#   log.sh "Message text" ["Calling script name"]
#
# Logs format:
#   {timestamp} [{calling_script}] {message}
#   If calling script is not provided, brackets are omitted.

LOG_FILE="/usr/local/bin/generic/logs"

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
