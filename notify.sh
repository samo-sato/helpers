#!/bin/bash

# This ensures env variables are present even in the minimal service execution context
# When this lines were missing, UPS related services failed to execute pre-defined scripts correctly on power events
if [ -f /etc/environment ]; then
    source /etc/environment
fi

NTFY_SERVER="https://ntfy.sh" # Third party notification service
TOPIC="$NTFY_TOPIC" # Must be defined globally in environment
LOG_SCRIPT="/opt/helpers/log.sh" # Path to external script used for logging
MESSAGE="" # Default notification message
TITLE="Notification" # Default title of notification message
TAGS="" # Default comma separated tags (https://docs.ntfy.sh/emojis/)
PRIORITY=3 # Default priority of the notification; 1 to 5 (low to high)

# --- Helper function for errors ---
# Prints to stderr, logs the error, and exits with the given status (default 1).
error_exit() {
    local message="ERROR: $1"
    local status=${2:-1}

    # 1. Print error to Standard Error (>&2) for immediate visibility
    echo "$message" >&2

    # 2. Log the error using the external log script
    "$LOG_SCRIPT" -m "$message" -p "$0"

    # 3. Exit with the appropriate non-zero status code
    exit "$status"
}

HELP_TEXT=$(cat <<'EOF'
Usage: ./notify.sh -m "Message" [-t "Title"] [-g "tag1,tag2"] [-p "Priority"]

Options:
  -m    Message (required)
  -t    Title (optional, default: "Notification")
  -g    Tags (optional, comma-separated, e.g. "door,warning")
  -p    Priority (optional, default: 3, range: 1–5)
  -h    Show this help

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
    # MODIFICATION: Changed exit 0 to use error_exit to log failure.
    error_exit "Missing required arguments. Run with -h for usage." 1
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

# --- Validation ---
if [[ -z "$MESSAGE" ]]; then
    # Use the error function to print and log the required error
    error_exit "Message (-m) is required." 1
fi
if [[ -z "$TOPIC" ]]; then
    # Use the error function if the required environment variable is missing
    error_exit "Environment variable NTFY_TOPIC is not defined." 1
fi


# Convert comma-separated tags into JSON array if provided
if [[ -n "$TAGS" ]]; then
    # Ensure tag handling uses robust quoting
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

# Send request and capture HTTP response code and curl's internal exit status
# -s: Silent mode, -o /dev/null: discard response body, -w "%{http_code}": write status code
RESPONSE=$(/usr/bin/curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "$NTFY_SERVER/")

CURL_EXIT_STATUS=$?

# --- Check 1: Did the curl command itself fail? ---
if [ $CURL_EXIT_STATUS -ne 0 ]; then
    # Curl failed (e.g., DNS failure, timeout, or 'curl' command not found in PATH)
    error_exit "curl command failed with exit code $CURL_EXIT_STATUS. Check network connectivity or absolute path to curl." $CURL_EXIT_STATUS
fi

# --- Check 2: Was the HTTP response code a success? ---
if [[ "$RESPONSE" == "200" || "$RESPONSE" == "201" ]]; then
    LOG_MSG="SUCCESS: Sent notification (Title: '$TITLE', Message: '$MESSAGE')"
    "$LOG_SCRIPT" -m "$LOG_MSG" -p "$0"
    exit 0
else
    # HTTP failure (e.g., 400 Bad Request, 404 Not Found)
    error_exit "Could not send notification (HTTP $RESPONSE). Check NTFY_TOPIC validity." 1
fi
