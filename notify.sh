#!/bin/bash

NTFY_SERVER="https://ntfy.sh"
TOPIC="$NTFY_TOPIC"   # Must be defined globally in environment
LOG_SCRIPT="/opt/helpers/log.sh"

# --- Defaults ---
MESSAGE=""
TITLE="Notification"
TAGS=""
PRIORITY=3

HELP_TEXT=$(cat <<'EOF'
Usage: ./notify.sh -m "Message" [-t "Title"] [-g "tag1,tag2"] [-p "Priority"]

Options:
  -m   Message (required)
  -t   Title (optional, default: "Notification")
  -g   Tags (optional, comma-separated, e.g. "door,warning")
  -p   Priority (optional, default: 3, range: 1–5)
  -h   Show this help

Examples:
  ./notify.sh -m "Disk space low"
  ./notify.sh -m "Door is open!" -t "Alert" -g "door,warning" -p 4
EOF
)

show_help() {
    echo "$HELP_TEXT"
}

# --- Show help if no args ---
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

# --- Parse options ---
while getopts "m:t:g:p:h" opt; do
  case $opt in
    m) MESSAGE="$OPTARG" ;;
    t) TITLE="$OPTARG" ;;
    g) TAGS="$OPTARG" ;;
    p) PRIORITY="$OPTARG" ;;
    h) show_help; exit 0 ;;
    *) show_help; exit 1 ;;
  esac
done

# --- Validate ---
if [[ -z "$MESSAGE" ]]; then
    ERR="Error: Message (-m) is required."
    echo "$ERR"
    "$LOG_SCRIPT" -m "$ERR" -p "$0"
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

# Log result
if [[ "$RESPONSE" == "200" || "$RESPONSE" == "201" ]]; then
    LOG_MSG="SUCCESS: Sent notification (Title: '$TITLE', Message: '$MESSAGE')"
    "$LOG_SCRIPT" -m "$LOG_MSG" -p "$0"
    exit 0
else
    LOG_MSG="FAILURE: Could not send notification (HTTP $RESPONSE)"
    "$LOG_SCRIPT" -m "$LOG_MSG" -p "$0"
    exit 1
fi
