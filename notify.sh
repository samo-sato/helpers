#!/bin/bash

# Universal notification sender via ntfy

# Parameters:
#   1 -> Message  (mandatory)
#   2 -> Title    (optional; default: "Notification")
#   3 -> Tags     (optional; comma-separated: "tag1,tag2"; example: "floppy_disk,warning"; full tag list: https://docs.ntfy.sh/emojis/)
#   4 -> Priority (optional; default: 3; possible values: 1,2,3,4,5; higher = max priority)

# Example:
#   notify "Disk space low" "Alert" "warning,disk" 4

NTFY_SERVER="https://ntfy.sh"
TOPIC="$NTFY_TOPIC"   # Must be defined globally in environment
LOG_SCRIPT="/opt/helpers/log.sh"

# --- Parameters ---
MESSAGE="$1"
TITLE="${2:-Notification}"
TAGS="$3"
PRIORITY="${4:-3}"

if [[ -z "$MESSAGE" ]]; then
    ERR="Error: Message is required."
    echo "$ERR"
    "$LOG_SCRIPT" "$ERR" "$0"
    exit 1
fi

# Convert comma-separated tags into JSON array if provided
if [[ -n "$TAGS" ]]; then
    TAGS_JSON=$(printf '"%s",' ${TAGS//,/ })
    TAGS_JSON="[${TAGS_JSON%,}]"
else
    TAGS_JSON="[]"
fi

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "topic": "$TOPIC",
  "message": "$MESSAGE",
  "title": "$TITLE",
  "tags": $TAGS_JSON,
  "priority": $PRIORITY
}
EOF
)

# Send request
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$NTFY_SERVER/")

# Log and echo result
if [[ "$RESPONSE" == "200" || "$RESPONSE" == "201" ]]; then
    LOG_MSG="SUCCESS: Sent notification (Title: '$TITLE', Message: '$MESSAGE')"
    echo "$LOG_MSG"
    "$LOG_SCRIPT" "$LOG_MSG" "$0"
    exit 0
else
    LOG_MSG="FAILURE: Could not send notification (HTTP $RESPONSE)"
    echo "$LOG_MSG"
    "$LOG_SCRIPT" "$LOG_MSG" "$0"
    exit 1
fi
