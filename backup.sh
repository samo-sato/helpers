#!/bin/bash

###############################################################################
# backup.sh - Linux backup tool
# Creates compressed tar.gz backups with configurable include/exclude paths,
# file size constraints, and age constraints.
###############################################################################

set -euo pipefail

# Script version
VERSION="1.0.0"

# Global variables
SCRIPT_NAME="backup"
DESTINATION=""
INCLUDE_PATHS=()
EXCLUDE_PATHS=()
PATHS_CONFIG=""
SMALLER_SIZE=""
LARGER_SIZE=""
NEWER_DATE=""
OLDER_DATE=""
DRY_RUN=false
VERBOSE=true
LOG_FILE=""
BACKUP_START_TIME=""
FILES_BACKED_UP=0
FILE_LIST_PATH=""
EXCLUDE_LIST_PATH=""
NEWER_FLAG_USED=false
OLDER_FLAG_USED=false
SMALLER_FLAG_USED=false
LARGER_FLAG_USED=false
KEEP_LAST=""
KEEP_HOURLY=""
KEEP_DAILY=""
KEEP_WEEKLY=""
KEEP_MONTHLY=""
KEEP_YEARLY=""

###############################################################################
# Helper Functions
###############################################################################

# Normalize path by removing trailing slash
normalize_path() {
    local path="$1"
    # Remove trailing slash if present
    echo "${path%/}"
}

# Print error message and exit
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Print verbose message
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
}

# Log message to file
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -n "$LOG_FILE" ] && [ -w "$(dirname "$LOG_FILE")" ] 2>/dev/null; then
        echo "$timestamp $1" >> "$LOG_FILE" 2>/dev/null || verbose "$1"
    else
        verbose "$1"
    fi
}

# Start logging - BACKUP_START_TIME is set here, but first log message is after validate_destination()
BACKUP_START_TIME=$(date +%s)

# Print usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME <destination> [OPTIONS]

Create compressed tar.gz backups with configurable paths, size, age constraints,
and automatic backup retention/deletion.

ARGUMENTS:
    destination              Backup destination directory (must exist)

OPTIONS:
    --include <path>         Include path in backup (can be repeated)
    --exclude <path>         Exclude path from backup (can be repeated)
    --paths <file>           YAML config file with include/exclude paths
                            (mutually exclusive with --include/--exclude)
    
    --smaller <size>         Only include files smaller than <size> MB
    --larger <size>          Only include files larger than <size> MB
                            (--smaller and --larger are mutually exclusive)
    
    --newer [date|days]      Only include files newer than date/days
                            If no value: use latest backup timestamp from destination
                            If no backups exist: flag is ignored (no time constraint)
                            Date format: YYYY-MM-DD HH:MM
                            Days format: number (e.g., 7 or 0.5)
    --older <date|days>      Only include files older than date/days
                            Requires a value (date or days) - cannot be used without value
                            (--newer and --older are mutually exclusive)
    
    --keep-last <n>          Keep the last N backup archives (most recent)
    --keep-hourly <n>        Keep N most recent backups per hour
    --keep-daily <n>         Keep N most recent backups per day
    --keep-weekly <n>        Keep N most recent backups per week
    --keep-monthly <n>       Keep N most recent backups per month
    --keep-yearly <n>        Keep N most recent backups per year
                            (Multiple retention policies can be combined using
                            intersection logic: --keep-last applies first, then
                            time-based policies apply to remaining backups)
    
    --dry-run                Show what would be backed up/deleted without
                            creating backup or deleting files
    --quiet, -q              Disable verbose output (only show errors and logs)
    --help, -h               Show this help message

EXAMPLES:
    $SCRIPT_NAME /home/bob/backups --include "/home/bob/Documents" --exclude "/home/bob/Documents/Tmp/"
    $SCRIPT_NAME /home/bob/backups --paths /home/bob/paths.yaml --smaller 2 --newer 365
    $SCRIPT_NAME /home/bob/backups --include "/" --exclude "/home/" --dry-run
    $SCRIPT_NAME /home/bob/backups --paths mypaths.yaml --keep-last 5 --keep-monthly 2

EXAMPLE OF YAML FILE: "utils/config/backup/paths.yaml.example"

NOTES:
    - Must be run with sudo
    - At least one include path is required (--include or --paths)
    - Backup files are named: YYYY-MM-DD_HH-MM-SS_backup.tar.gz
    - Full paths are preserved in backup archive
    - Logs are written to backup.log in destination directory
    - Autodeletion only affects files matching the exact backup naming pattern
    - Autodeletion runs after backup creation (new backup is never deleted)
    - In dry-run mode, autodeletion accounts for the new backup that would be created
    - YAML config files support both flat and nested structures, including list format (- /path)
EOF
}

###############################################################################
# Validation Functions
###############################################################################

# Check if running with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run with sudo"
    fi
}

# Check for required commands
check_dependencies() {
local missing_deps=()
    # List of all external binaries used in the script
    local dependencies=(tar find stat date bc readlink du wc grep sort sed cut mktemp rm mv head)
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Specific check for GNU readlink behavior (critical for this script)
    if command -v readlink >/dev/null 2>&1; then
        if ! readlink -f / 2>/dev/null >/dev/null; then
             echo "ERROR: The installed 'readlink' does not support the '-f' flag (GNU coreutils required)." >&2
             echo "       On macOS, install coreutils (brew install coreutils) and use 'greadlink'." >&2
             exit 1
        fi
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error_exit "Missing required commands: ${missing_deps[*]}"
    fi
}

# Validate destination exists
validate_destination() {
    if [ -z "$DESTINATION" ]; then
        error_exit "Destination path is required"
    fi
    
    if [ ! -d "$DESTINATION" ]; then
        error_exit "Destination directory does not exist: $DESTINATION"
    fi
    
    # Check if destination is writable
    if [ ! -w "$DESTINATION" ]; then
        error_exit "Destination directory is not writable: $DESTINATION"
    fi
    
    # Make destination absolute path
    DESTINATION=$(readlink -f "$DESTINATION")
    LOG_FILE="$DESTINATION/backup.log"
}

# Validate mutually exclusive options
validate_options() {
    # Note: --paths vs --include/--exclude check is done BEFORE YAML parsing in main()
    
    # Check if any paths are defined
    if [ -z "$PATHS_CONFIG" ] && [ ${#INCLUDE_PATHS[@]} -eq 0 ] && [ ${#EXCLUDE_PATHS[@]} -eq 0 ]; then
        error_exit "No paths defined. Use --include/--exclude or --paths to specify paths to backup"
    fi
    
    # Require at least one include path (prevent dangerous find / -type f)
    if [ ${#INCLUDE_PATHS[@]} -eq 0 ]; then
        error_exit "At least one include path is required. Use --include or --paths to specify paths to backup"
    fi
    
    # Check --smaller vs --larger (check flag usage, not just values)
    if [ "$SMALLER_FLAG_USED" = true ] && [ "$LARGER_FLAG_USED" = true ]; then
        error_exit "Cannot use --smaller and --larger flags together"
    fi
    
    # Check --newer vs --older (check flag usage, not just values)
    if [ "$NEWER_FLAG_USED" = true ] && [ "$OLDER_FLAG_USED" = true ]; then
        error_exit "Cannot use --newer and --older flags together"
    fi
}

# Validate path exists (log warning if not, but continue)
validate_path() {
    local path="$1"
    local path_type="$2"
    local normalized_path=$(normalize_path "$path")
    
    if [ ! -e "$normalized_path" ]; then
        log_message "Warning: $path_type path does not exist: $normalized_path"
        return 1
    fi
    return 0
}

###############################################################################
# YAML Parsing Functions
###############################################################################

# Parse YAML config file (supports both flat and nested structures)
parse_yaml_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        error_exit "Config file does not exist: $config_file"
    fi
    
    local in_include=false
    local in_exclude=false
    local in_paths=false
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Store original line for indentation detection
        local original_line="$line"
        # Remove trailing whitespace only (keep leading for indentation detection)
        line=$(echo "$line" | sed 's/[[:space:]]*$//')
        
        # Trim for pattern matching
        local trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//')
        
        # Check for nested structure: paths: section
        if [[ "$trimmed_line" =~ ^paths:[[:space:]]*$ ]]; then
            in_paths=true
            in_include=false
            in_exclude=false
            continue
        fi
        
        # Check for flat structure: include: or exclude: at root level (no indentation)
        if [[ "$trimmed_line" =~ ^include:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]+ ]]; then
            in_include=true
            in_exclude=false
            in_paths=false
            continue
        elif [[ "$trimmed_line" =~ ^exclude:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]+ ]]; then
            in_include=false
            in_exclude=true
            in_paths=false
            continue
        fi
        
        # Handle nested structure: paths.include: or paths.exclude: (with indentation)
        if [ "$in_paths" = true ]; then
            if [[ "$trimmed_line" =~ ^include:[[:space:]]*(.+) ]]; then
                local path_value="${BASH_REMATCH[1]}"
                # Handle YAML list format: strip leading "- " if present
                if [[ "$path_value" =~ ^-[[:space:]]+(.+) ]]; then
                    path_value="${BASH_REMATCH[1]}"
                fi
                # Remove quotes if present
                path_value=$(echo "$path_value" | sed "s/^['\"]//;s/['\"]$//")
                if [ -n "$path_value" ]; then
                    INCLUDE_PATHS+=("$(normalize_path "$path_value")")
                fi
                continue
            elif [[ "$trimmed_line" =~ ^exclude:[[:space:]]*(.+) ]]; then
                local path_value="${BASH_REMATCH[1]}"
                # Handle YAML list format: strip leading "- " if present
                if [[ "$path_value" =~ ^-[[:space:]]+(.+) ]]; then
                    path_value="${BASH_REMATCH[1]}"
                fi
                # Remove quotes if present
                path_value=$(echo "$path_value" | sed "s/^['\"]//;s/['\"]$//")
                if [ -n "$path_value" ]; then
                    EXCLUDE_PATHS+=("$(normalize_path "$path_value")")
                fi
                continue
            elif [[ "$trimmed_line" =~ ^-[[:space:]]+(.+) ]]; then
                # Handle YAML list format directly under paths: section
                local path_value="${BASH_REMATCH[1]}"
                # Remove quotes if present
                path_value=$(echo "$path_value" | sed "s/^['\"]//;s/['\"]$//")
                # Determine if this is include or exclude based on context
                # (This handles cases where list items are directly under paths:)
                # For now, we'll need to track which section we're in
                # This is a simplified approach - assumes include if not specified
                if [ -n "$path_value" ]; then
                    INCLUDE_PATHS+=("$(normalize_path "$path_value")")
                fi
                continue
            fi
        fi
        
        # Handle flat structure: paths listed under include: or exclude:
        if [ "$in_include" = true ] && [ -n "$trimmed_line" ]; then
            # Handle YAML list format: strip leading "- " if present
            if [[ "$trimmed_line" =~ ^-[[:space:]]+(.+) ]]; then
                trimmed_line="${BASH_REMATCH[1]}"
            fi
            # Remove quotes if present
            local path_value=$(echo "$trimmed_line" | sed "s/^['\"]//;s/['\"]$//")
            if [ -n "$path_value" ]; then
                INCLUDE_PATHS+=("$(normalize_path "$path_value")")
            fi
        elif [ "$in_exclude" = true ] && [ -n "$trimmed_line" ]; then
            # Handle YAML list format: strip leading "- " if present
            if [[ "$trimmed_line" =~ ^-[[:space:]]+(.+) ]]; then
                trimmed_line="${BASH_REMATCH[1]}"
            fi
            # Remove quotes if present
            local path_value=$(echo "$trimmed_line" | sed "s/^['\"]//;s/['\"]$//")
            if [ -n "$path_value" ]; then
                EXCLUDE_PATHS+=("$(normalize_path "$path_value")")
            fi
        fi
    done < "$config_file"
    
    if [ ${#INCLUDE_PATHS[@]} -eq 0 ] && [ ${#EXCLUDE_PATHS[@]} -eq 0 ]; then
        error_exit "No valid include or exclude paths found in config file"
    fi
}

###############################################################################
# Date and Time Functions
###############################################################################

# Get last backup date from filename
get_last_backup_date() {
    local last_backup=""
    local last_date=""
    local last_timestamp=0
    
    # Find all backup files matching pattern YYYY-MM-DD_HH-MM-SS_backup.tar.gz
    # Use both filename and modification time to determine the most recent backup
    while IFS= read -r file; do
        local current_date=$(basename "$file" | sed 's/_backup\.tar\.gz$//')
        # Validate date format
        if [[ "$current_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
            # Get file modification time as fallback
            local file_timestamp=$(stat -c %Y "$file" 2>/dev/null || echo "0")
            
            if [ -z "$last_backup" ]; then
                last_backup="$file"
                last_date="$current_date"
                last_timestamp="$file_timestamp"
            else
                # Compare by filename first (lexicographic comparison works for ISO date format)
                # If filenames are equal or very close, use modification time
                if [[ "$current_date" > "$last_date" ]] || \
                   ([[ "$current_date" == "$last_date" ]] && [ "$file_timestamp" -gt "$last_timestamp" ]); then
                    last_backup="$file"
                    last_date="$current_date"
                    last_timestamp="$file_timestamp"
                fi
            fi
        fi
    done < <(find "$DESTINATION" -maxdepth 1 -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]_backup.tar.gz" 2>/dev/null | sort)
    
    if [ -n "$last_date" ]; then
        # Convert YYYY-MM-DD_HH-MM-SS to YYYY-MM-DD HH:MM:SS
        # Format: 2025-06-21_13-19-45 -> 2025-06-21 13:19:45
        # First replace underscore with space, then replace dashes in time part with colons
        # The time part is after the space, so we match HH-MM-SS and convert to HH:MM:SS
        echo "$last_date" | sed 's/_/ /' | sed 's/\([0-9][0-9]\)-\([0-9][0-9]\)-\([0-9][0-9]\)$/\1:\2:\3/'
    fi
}

# Parse date value (YYYY-MM-DD HH:MM or days as number)
parse_date_value() {
    local value="$1"
    local comparison="$2"  # "newer" or "older"
    
    # If empty, behavior depends on comparison type
    if [ -z "$value" ]; then
        if [ "$comparison" = "older" ]; then
            # --older requires a value, this should not happen (checked in argument parsing)
            error_exit "--older requires a date or days value"
        fi
        
        # For --newer without value, use last backup date if available
        # If no backup exists, return empty (flag will be ignored)
        local last_backup_date=$(get_last_backup_date)
        if [ -z "$last_backup_date" ]; then
            # No previous backup found - return empty to indicate flag should be ignored
            echo ""
            return
        fi
        echo "$last_backup_date"
        return
    fi
    
    # Check if it's a number (days, can be decimal)
    if [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        # Calculate date: days ago
        # Try GNU date first (Linux) - supports decimal days directly
        local date_result=""
        if date -d "$value days ago" '+%Y-%m-%d %H:%M:%S' >/dev/null 2>&1; then
            # GNU date supports decimal days directly
            date_result=$(date -d "$value days ago" '+%Y-%m-%d %H:%M:%S')
        else
            # BSD date (macOS): convert decimal days to hours and minutes
            if command -v bc >/dev/null 2>&1; then
                local total_hours=$(echo "$value * 24" | bc -l)
                local hours=$(echo "$total_hours" | cut -d. -f1)
                local minutes_decimal=$(echo "$total_hours - $hours" | bc -l)
                local minutes=$(echo "$minutes_decimal * 60" | bc -l | cut -d. -f1)
                
                # Build BSD date command
                if [ "$hours" -gt 0 ] && [ "$minutes" -gt 0 ]; then
                    date_result=$(date -v-${hours}H -v-${minutes}M '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
                elif [ "$hours" -gt 0 ]; then
                    date_result=$(date -v-${hours}H '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
                elif [ "$minutes" -gt 0 ]; then
                    date_result=$(date -v-${minutes}M '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
                else
                    # Less than a minute, use current time
                    date_result=$(date '+%Y-%m-%d %H:%M:%S')
                fi
                
                if [ -z "$date_result" ]; then
                    # Fallback: try as integer days
                    local int_days=$(echo "$value" | cut -d. -f1)
                    if [ "$int_days" -gt 0 ]; then
                        date_result=$(date -v-${int_days}d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
                    fi
                fi
            fi
            
            if [ -z "$date_result" ]; then
                error_exit "Invalid days value or unsupported date command: $value"
            fi
        fi
        echo "$date_result"
    # Check if it's date format YYYY-MM-DD HH:MM
    elif [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}$ ]]; then
        echo "$value:00"
    else
        error_exit "Invalid date format: $value (expected YYYY-MM-DD HH:MM or number of days)"
    fi
}

# Get timestamp for file comparison
get_file_timestamp() {
    local file="$1"
    stat -c %Y "$file" 2>/dev/null || echo "0"
}

# Convert date string to timestamp
date_to_timestamp() {
    local date_str="$1"
    
    if [ -z "$date_str" ]; then
        echo "0"
        return
    fi
    
    # Try GNU date first (Linux) - supports flexible date formats
    local timestamp=$(date -d "$date_str" +%s 2>/dev/null)
    
    if [ -z "$timestamp" ] || [ "$timestamp" = "0" ]; then
        # Try BSD date (macOS) - requires explicit format
        # Try with seconds format first
        if [[ "$date_str" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
            timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date_str" +%s 2>/dev/null)
        fi
        
        # If still failed, try without seconds
        if [ -z "$timestamp" ] || [ "$timestamp" = "0" ]; then
            if [[ "$date_str" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2} ]]; then
                timestamp=$(date -j -f "%Y-%m-%d %H:%M" "$date_str" +%s 2>/dev/null)
            fi
        fi
    fi
    
    # If all attempts failed, return 0
    if [ -z "$timestamp" ] || [ "$timestamp" = "0" ]; then
        echo "0"
    else
        echo "$timestamp"
    fi
}

###############################################################################
# File Filtering Functions
###############################################################################

# Check if file matches size constraint
matches_size_constraint() {
    local file="$1"
    
    if [ -z "$SMALLER_SIZE" ] && [ -z "$LARGER_SIZE" ]; then
        return 0
    fi
    
    # Get file size in bytes
    local size_bytes=$(stat -c %s "$file" 2>/dev/null || echo "0")
    
    # Validate size_bytes is numeric and positive
    if ! [[ "$size_bytes" =~ ^[0-9]+$ ]] || [ "$size_bytes" -eq 0 ]; then
        # Invalid or zero size - skip this file
        return 1
    fi
    
    # Calculate size in MB with error handling
    local size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$size_mb" ]; then
        # bc failed or returned empty - skip this file
        return 1
    fi
    
    if [ -n "$SMALLER_SIZE" ]; then
        local comparison=$(echo "$size_mb < $SMALLER_SIZE" | bc -l 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$comparison" ]; then
            # bc failed - skip this file
            return 1
        fi
        if (( comparison )); then
            return 0
        else
            return 1
        fi
    fi
    
    if [ -n "$LARGER_SIZE" ]; then
        local comparison=$(echo "$size_mb > $LARGER_SIZE" | bc -l 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$comparison" ]; then
            # bc failed - skip this file
            return 1
        fi
        if (( comparison )); then
            return 0
        else
            return 1
        fi
    fi
    
    return 0
}

# Check if file matches age constraint
matches_age_constraint() {
    local file="$1"
    
    # If no age constraints are set, include the file
    if [ "$NEWER_FLAG_USED" != true ] && [ "$OLDER_FLAG_USED" != true ]; then
        return 0
    fi
    
    # If flags are used but dates are not set (shouldn't happen after parsing, but safety check)
    if [ "$NEWER_FLAG_USED" = true ] && [ -z "$NEWER_DATE" ]; then
        return 0
    fi
    if [ "$OLDER_FLAG_USED" = true ] && [ -z "$OLDER_DATE" ]; then
        return 0
    fi
    
    local file_timestamp=$(get_file_timestamp "$file")
    local comparison_timestamp=""
    
    if [ "$NEWER_FLAG_USED" = true ] && [ -n "$NEWER_DATE" ]; then
        comparison_timestamp=$(date_to_timestamp "$NEWER_DATE")
        if [ "$comparison_timestamp" = "0" ] || [ -z "$comparison_timestamp" ]; then
            # Invalid timestamp, include file to be safe (shouldn't happen after validation)
            return 0
        fi
        # For --newer: include file if file_timestamp > comparison_timestamp (file is newer)
        # file_timestamp is modification time in seconds since epoch
        # comparison_timestamp is the date constraint in seconds since epoch
        if [ "$file_timestamp" -gt "$comparison_timestamp" ]; then
            return 0
        else
            return 1
        fi
    fi
    
    if [ "$OLDER_FLAG_USED" = true ] && [ -n "$OLDER_DATE" ]; then
        comparison_timestamp=$(date_to_timestamp "$OLDER_DATE")
        if [ "$comparison_timestamp" = "0" ] || [ -z "$comparison_timestamp" ]; then
            # Invalid timestamp, include file to be safe
            return 0
        fi
        if [ "$file_timestamp" -lt "$comparison_timestamp" ]; then
            return 0
        else
            return 1
        fi
    fi
    
    return 0
}

# Check if path should be included
should_include_path() {
    local path="$1"
    local normalized_path=$(normalize_path "$path")
    normalized_path=$(readlink -f "$normalized_path" 2>/dev/null || echo "$normalized_path")
    
    # Check exclude patterns first
    for exclude in "${EXCLUDE_PATHS[@]}"; do
        local normalized_exclude=$(normalize_path "$exclude")
        normalized_exclude=$(readlink -f "$normalized_exclude" 2>/dev/null || echo "$normalized_exclude")
        
        # Check for exact match or if the path is a subdirectory of the excluded path
        if [[ "$normalized_path" == "$normalized_exclude" || "$normalized_path" == "$normalized_exclude"/* ]]; then
            return 1
        fi
    done
    
    # If no include paths, include everything (except excluded)
    if [ ${#INCLUDE_PATHS[@]} -eq 0 ]; then
        return 0
    fi
    
    # Check include patterns
    for include in "${INCLUDE_PATHS[@]}"; do
        local normalized_include=$(normalize_path "$include")
        normalized_include=$(readlink -f "$normalized_include" 2>/dev/null || echo "$normalized_include")
        if [[ "$normalized_path" == "$normalized_include"* ]]; then
            return 0
        fi
    done
    
    return 1
}

###############################################################################
# Backup Creation Functions
###############################################################################

# Create file list for backup
create_file_list() {
    local temp_list=$(mktemp)
    local temp_exclude_list=$(mktemp)
    
    # Build exclude list for tar (absolute paths)
    for exclude in "${EXCLUDE_PATHS[@]}"; do
        local normalized_exclude=$(normalize_path "$exclude")
        validate_path "$normalized_exclude" "Exclude" || continue
        local abs_exclude=$(readlink -f "$normalized_exclude" 2>/dev/null || echo "$normalized_exclude")
        echo "$abs_exclude" >> "$temp_exclude_list"
    done
    
    # Process each include path (at least one is required - validated earlier)
    for include in "${INCLUDE_PATHS[@]}"; do
        local normalized_include=$(normalize_path "$include")
        validate_path "$normalized_include" "Include" || continue
        
        local abs_include=$(readlink -f "$normalized_include" 2>/dev/null || echo "$normalized_include")
        
        if [ -f "$abs_include" ]; then
            # Single file
            if should_include_path "$abs_include" && matches_size_constraint "$abs_include" && matches_age_constraint "$abs_include"; then
                echo "$abs_include" >> "$temp_list"
            fi
        elif [ -d "$abs_include" ]; then
            # Directory - find all files
            verbose "Scanning directory: $abs_include"
            find "$abs_include" -type f 2>/dev/null > "$temp_list.tmp" || true
            while IFS= read -r file; do
                if should_include_path "$file" && matches_size_constraint "$file" && matches_age_constraint "$file"; then
                    echo "$file" >> "$temp_list"
                fi
            done < "$temp_list.tmp"
            rm -f "$temp_list.tmp"
        fi
    done

    # Return both file paths via global variables
    FILE_LIST_PATH="$temp_list"
    EXCLUDE_LIST_PATH="$temp_exclude_list"
}

# Create backup
create_backup() {
    local backup_name=$(date '+%Y-%m-%d_%H-%M-%S')_backup.tar.gz
    local backup_path="$DESTINATION/$backup_name"
    
    verbose "Creating backup: $backup_name"
    log_message "Creating backup archive: $backup_name"
    
    # Create file list
    create_file_list
    local file_list="$FILE_LIST_PATH"
    local exclude_list="$EXCLUDE_LIST_PATH"
    
    # Small delay to ensure file list is complete
    sync
    
    # Count files
    FILES_BACKED_UP=$(wc -l < "$file_list" 2>/dev/null || echo "0")
    log_message "Files to backup: $FILES_BACKED_UP"
    
    if [ "$DRY_RUN" = true ]; then
        verbose "DRY RUN: Would create backup at $backup_path"
        log_message "DRY RUN: Would create backup at $backup_path"
        verbose "DRY RUN: Would backup $FILES_BACKED_UP files"
        # Show sample of files that would be backed up
        if [ "$FILES_BACKED_UP" -gt 0 ] && [ "$FILES_BACKED_UP" -le 20 ]; then
            verbose "Files that would be backed up:"
            head -n 10 "$file_list" | while IFS= read -r file; do
                verbose "  $file"
            done
        fi
        if [ "$FILES_BACKED_UP" -eq 0 ]; then
            log_message "DRY RUN: Warning - No files would be backed up (all paths invalid or filtered out)"
            verbose "DRY RUN: Warning - No files would be backed up"
        fi
        rm -f "$file_list" "$exclude_list"
        return
    fi
    
    if [ "$FILES_BACKED_UP" -eq 0 ]; then
        log_message "ERROR: No files to backup - all paths are invalid or filtered out by constraints"
        rm -f "$file_list" "$exclude_list"
        error_exit "No files to backup. Check that include paths exist and match your size/age constraints."
    fi
    
    # Create tar archive with maximum compression
    # Use --absolute-names to preserve full paths
    verbose "Found $FILES_BACKED_UP files..."
    
    # Create tar command
    # Use process substitution or file lists for excludes
    local tar_excludes=()
    if [ -s "$exclude_list" ]; then
        while IFS= read -r exclude_path; do
            tar_excludes+=(--exclude="$exclude_path")
        done < "$exclude_list"
    fi
    # Execute tar command
    # Note: --exclude with --files-from works, but since we already filter the file list,
    # the excludes are redundant but kept as a safety measure
    local tar_stderr=$(mktemp)
    if tar -czf "$backup_path" --absolute-names --ignore-failed-read "${tar_excludes[@]}" --files-from="$file_list" 2>"$tar_stderr"; then
        local backup_size=$(du -h "$backup_path" | cut -f1)
        verbose "Backup created: $backup_path (size: $backup_size)"
        
        # Log any warnings from tar (non-fatal errors like permission denied on some files)
        if [ -s "$tar_stderr" ]; then
            # Count the number of warning lines
            local warning_count=$(wc -l < "$tar_stderr")
            # Output the summarized warning to terminal verbose
	    verbose "Some files could not be backed up [$warning_count item(s)]; see the logfile for more details"
            
            while IFS= read -r line; do
                log_message "tar warning: $line"
            done < "$tar_stderr"
        fi
        
        rm -f "$tar_stderr"
        log_message "Backup created: $backup_name (size: $backup_size)"
    else    
        log_message "Error creating backup archive"
        if [ -s "$tar_stderr" ]; then
            while IFS= read -r line; do
                log_message "tar error: $line"
                verbose "tar error: $line"
            done < "$tar_stderr"
        fi
        rm -f "$tar_stderr" "$backup_path" "$file_list" "$exclude_list"
        error_exit "Failed to create backup archive"
    fi
    
    # Cleanup
    rm -f "$file_list" "$exclude_list"
}

###############################################################################
# Autodeletion Functions
###############################################################################

# Parse backup filename and extract timestamp
# Returns timestamp in seconds since epoch, or empty if invalid
parse_backup_timestamp() {
    local filename="$1"
    local basename_file=$(basename "$filename")
    
    # Check if filename matches pattern: YYYY-MM-DD_HH-MM-SS_backup.tar.gz
    if [[ ! "$basename_file" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})_backup\.tar\.gz$ ]]; then
        return 1
    fi
    
    local year="${BASH_REMATCH[1]}"
    local month="${BASH_REMATCH[2]}"
    local day="${BASH_REMATCH[3]}"
    local hour="${BASH_REMATCH[4]}"
    local minute="${BASH_REMATCH[5]}"
    local second="${BASH_REMATCH[6]}"
    
    # Convert to timestamp (GNU date)
    local date_str="${year}-${month}-${day} ${hour}:${minute}:${second}"
    local timestamp=$(date -d "$date_str" +%s 2>/dev/null)
    
    if [ -z "$timestamp" ] || [ "$timestamp" = "0" ]; then
        # Try BSD date format
        timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$date_str" +%s 2>/dev/null || echo "")
    fi
    
    if [ -n "$timestamp" ] && [ "$timestamp" != "0" ]; then
        echo "$timestamp"
        return 0
    fi
    
    return 1
}

# Get all backup files with their timestamps
# Output format: timestamp|filepath (one per line, sorted by timestamp descending)
get_all_backups() {
    local backup_files=()
    local temp_output=$(mktemp)
    
    # Find all files matching the backup pattern in destination
    while IFS= read -r file; do
        if [ ! -f "$file" ]; then
            continue
        fi
        
        local timestamp=$(parse_backup_timestamp "$file")
        if [ -n "$timestamp" ] && [ "$timestamp" != "0" ]; then
            echo "${timestamp}|${file}"
        else
            # Log warning for files that match pattern but can't be parsed
            local filename=$(basename "$file")
            log_message "Warning: Could not parse timestamp from backup file: $filename (keeping undeleted)"
        fi
    done < <(find "$DESTINATION" -maxdepth 1 -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]_backup.tar.gz" 2>/dev/null) | sort -t'|' -k1 -rn > "$temp_output"
    
    # Output sorted results
    cat "$temp_output"
    rm -f "$temp_output"
}

# Apply --keep-last policy
apply_keep_last() {
    local count="$1"
    local backups_file="$2"
    local keep_file="$3"
    
    if [ -z "$count" ] || [ "$count" -le 0 ]; then
        return
    fi
    
    # Keep the first N backups (they're already sorted by timestamp descending)
    head -n "$count" "$backups_file" >> "$keep_file"
}

# Apply time-based retention policy (hourly, daily, weekly, monthly, yearly)
# $1: period type (hourly, daily, weekly, monthly, yearly)
# $2: count to keep per period
# $3: backups file (timestamp|filepath)
# $4: keep file (to append to)
# $5: already_kept file (backups already marked to keep, to exclude)
apply_time_based_retention() {
    local period_type="$1"
    local count="$2"
    local backups_file="$3"
    local keep_file="$4"
    local already_kept_file="$5"
    
    if [ -z "$count" ] || [ "$count" -le 0 ]; then
        return
    fi
    
    # Create a temporary file with backups not already kept
    local remaining_backups=$(mktemp)
    
    # Get list of already kept files (just the filepath part)
    local kept_paths=$(mktemp)
    if [ -s "$already_kept_file" ]; then
        cut -d'|' -f2- "$already_kept_file" | sort > "$kept_paths"
    else
        touch "$kept_paths"
    fi
    
    # Filter out already kept backups (maintain sort order - newest first)
    while IFS='|' read -r timestamp filepath; do
        if ! grep -Fxq "$filepath" "$kept_paths" 2>/dev/null; then
            echo "${timestamp}|${filepath}"
        fi
    done < "$backups_file" > "$remaining_backups"
    
    rm -f "$kept_paths"
    
    if [ ! -s "$remaining_backups" ]; then
        rm -f "$remaining_backups"
        return
    fi
    
    # Ensure remaining backups are sorted by timestamp descending (newest first)
    sort -t'|' -k1 -rn "$remaining_backups" > "${remaining_backups}.sorted"
    mv "${remaining_backups}.sorted" "$remaining_backups"
    
    # Group backups by time period and keep N most recent per period
    local current_period=""
    local period_backups=$(mktemp)
    
    while IFS='|' read -r timestamp filepath; do
        local period_key=""
        
        case "$period_type" in
            hourly)
                # Group by YYYY-MM-DD HH
                period_key=$(date -d "@$timestamp" '+%Y-%m-%d %H' 2>/dev/null || date -j -f "%s" "$timestamp" '+%Y-%m-%d %H' 2>/dev/null || echo "")
                ;;
            daily)
                # Group by YYYY-MM-DD
                period_key=$(date -d "@$timestamp" '+%Y-%m-%d' 2>/dev/null || date -j -f "%s" "$timestamp" '+%Y-%m-%d' 2>/dev/null || echo "")
                ;;
            weekly)
                # Group by YYYY-WW (year-week)
                period_key=$(date -d "@$timestamp" '+%Y-%V' 2>/dev/null || date -j -f "%s" "$timestamp" '+%Y-%V' 2>/dev/null || echo "")
                # Fallback if %V not supported
                if [ -z "$period_key" ]; then
                    local year=$(date -d "@$timestamp" '+%Y' 2>/dev/null || date -j -f "%s" "$timestamp" '+%Y' 2>/dev/null)
                    local week=$(date -d "@$timestamp" '+%U' 2>/dev/null || date -j -f "%s" "$timestamp" '+%U' 2>/dev/null)
                    period_key="${year}-W${week}"
                fi
                ;;
            monthly)
                # Group by YYYY-MM
                period_key=$(date -d "@$timestamp" '+%Y-%m' 2>/dev/null || date -j -f "%s" "$timestamp" '+%Y-%m' 2>/dev/null || echo "")
                ;;
            yearly)
                # Group by YYYY
                period_key=$(date -d "@$timestamp" '+%Y' 2>/dev/null || date -j -f "%s" "$timestamp" '+%Y' 2>/dev/null || echo "")
                ;;
        esac
        
        if [ -z "$period_key" ]; then
            continue
        fi
        
        if [ "$period_key" != "$current_period" ]; then
            # New period - process previous period's backups
            if [ -n "$current_period" ] && [ -s "$period_backups" ]; then
                # Keep N most recent from this period
                head -n "$count" "$period_backups" >> "$keep_file"
            fi
            # Start new period
            current_period="$period_key"
            > "$period_backups"
        fi
        
        echo "${timestamp}|${filepath}" >> "$period_backups"
    done < "$remaining_backups"
    
    # Process last period
    if [ -n "$current_period" ] && [ -s "$period_backups" ]; then
        head -n "$count" "$period_backups" >> "$keep_file"
    fi
    
    rm -f "$period_backups" "$remaining_backups"
}

# Delete old backups based on retention policies
delete_old_backups() {
    # Check if any retention policy is set
    if [ -z "$KEEP_LAST" ] && [ -z "$KEEP_HOURLY" ] && [ -z "$KEEP_DAILY" ] && \
       [ -z "$KEEP_WEEKLY" ] && [ -z "$KEEP_MONTHLY" ] && [ -z "$KEEP_YEARLY" ]; then
        return 0
    fi
    
    verbose "Applying retention policies..."
    log_message "Applying retention policies for autodeletion"
    
    # Get all backups sorted by timestamp (newest first)
    local all_backups=$(mktemp)
    get_all_backups > "$all_backups"
    
    # In dry-run mode, simulate the new backup that would be created
    if [ "$DRY_RUN" = true ]; then
        local new_backup_name=$(date '+%Y-%m-%d_%H-%M-%S')_backup.tar.gz
        local new_backup_path="$DESTINATION/$new_backup_name"
        local new_backup_timestamp=$(parse_backup_timestamp "$new_backup_name")
        if [ -n "$new_backup_timestamp" ] && [ "$new_backup_timestamp" != "0" ]; then
            # Add the new backup to the list (it will be the newest)
            echo "${new_backup_timestamp}|${new_backup_path}" >> "$all_backups"
            # Re-sort to ensure newest first
            sort -t'|' -k1 -rn "$all_backups" > "${all_backups}.sorted"
            mv "${all_backups}.sorted" "$all_backups"
        fi
    fi
    
    if [ ! -s "$all_backups" ]; then
        verbose "No backups found for retention policy"
        rm -f "$all_backups"
        return 0
    fi
    
    local total_backups=$(wc -l < "$all_backups")
    verbose "Found $total_backups backup(s) to evaluate"
    
    # File to track which backups to keep
    local keep_backups=$(mktemp)
    
    # Apply retention policies in order (Option B: Intersection)
    # 1. First apply --keep-last
    if [ -n "$KEEP_LAST" ]; then
        apply_keep_last "$KEEP_LAST" "$all_backups" "$keep_backups"
        log_message "Keeping last $KEEP_LAST backup(s)"
    fi
    
    # 2. Then apply time-based policies to remaining backups
    if [ -n "$KEEP_HOURLY" ]; then
        apply_time_based_retention "hourly" "$KEEP_HOURLY" "$all_backups" "$keep_backups" "$keep_backups"
        log_message "Keeping $KEEP_HOURLY most recent backup(s) per hour"
    fi
    
    if [ -n "$KEEP_DAILY" ]; then
        apply_time_based_retention "daily" "$KEEP_DAILY" "$all_backups" "$keep_backups" "$keep_backups"
        log_message "Keeping $KEEP_DAILY most recent backup(s) per day"
    fi
    
    if [ -n "$KEEP_WEEKLY" ]; then
        apply_time_based_retention "weekly" "$KEEP_WEEKLY" "$all_backups" "$keep_backups" "$keep_backups"
        log_message "Keeping $KEEP_WEEKLY most recent backup(s) per week"
    fi
    
    if [ -n "$KEEP_MONTHLY" ]; then
        apply_time_based_retention "monthly" "$KEEP_MONTHLY" "$all_backups" "$keep_backups" "$keep_backups"
        log_message "Keeping $KEEP_MONTHLY most recent backup(s) per month"
    fi
    
    if [ -n "$KEEP_YEARLY" ]; then
        apply_time_based_retention "yearly" "$KEEP_YEARLY" "$all_backups" "$keep_backups" "$keep_backups"
        log_message "Keeping $KEEP_YEARLY most recent backup(s) per year"
    fi
    
    # Get list of files to keep (just filepaths, sorted)
    local keep_paths=$(mktemp)
    if [ -s "$keep_backups" ]; then
        cut -d'|' -f2- "$keep_backups" | sort -u > "$keep_paths"
    else
        touch "$keep_paths"
    fi
    
    # Find backups to delete
    local to_delete=$(mktemp)
    while IFS='|' read -r timestamp filepath; do
        if ! grep -Fxq "$filepath" "$keep_paths" 2>/dev/null; then
            echo "$filepath"
        fi
    done < "$all_backups" > "$to_delete"
    
    local delete_count=$(wc -l < "$to_delete" 2>/dev/null || echo "0")
    local keep_count=$(wc -l < "$keep_paths" 2>/dev/null || echo "0")
    
    if [ "$delete_count" -eq 0 ]; then
        verbose "No backups to delete"
        log_message "No backups to delete (keeping all $keep_count backup(s))"
        rm -f "$all_backups" "$keep_backups" "$keep_paths" "$to_delete"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        verbose "DRY RUN: Would delete $delete_count backup(s):"
        log_message "DRY RUN: Would delete $delete_count backup(s):"
        while IFS= read -r filepath; do
            local filename=$(basename "$filepath")
            # Skip the simulated new backup in deletion list (it would be created, not deleted)
            if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_backup\.tar\.gz$ ]]; then
                local file_timestamp=$(parse_backup_timestamp "$filename")
                local new_backup_name=$(date '+%Y-%m-%d_%H-%M-%S')_backup.tar.gz
                local new_backup_timestamp=$(parse_backup_timestamp "$new_backup_name")
                # If this is the new backup we simulated, skip it
                if [ "$file_timestamp" = "$new_backup_timestamp" ]; then
                    continue
                fi
            fi
            verbose "  Would delete: $filename"
            log_message "  Would delete: $filename"
        done < "$to_delete"
        verbose "DRY RUN: Would keep $keep_count backup(s) (including the new backup that would be created)"
        log_message "DRY RUN: Would keep $keep_count backup(s) (including the new backup that would be created)"
    else
        verbose "Deleting $delete_count old backup(s)..."
        log_message "Deleting $delete_count old backup(s), keeping $keep_count backup(s)"
        
        local deleted=0
        local failed=0
        
        while IFS= read -r filepath; do
            local filename=$(basename "$filepath")
            
            # Verify it's still a regular file matching the pattern
            if [ ! -f "$filepath" ]; then
                log_message "Warning: Backup file no longer exists: $filename"
                continue
            fi
            
            # Double-check filename pattern before deletion
            if [[ ! "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_backup\.tar\.gz$ ]]; then
                log_message "Warning: Skipping deletion of file with invalid pattern: $filename"
                failed=$((failed + 1))
                continue
            fi
            
            # Delete the file
            if rm -f "$filepath" 2>/dev/null; then
                deleted=$((deleted + 1))
                log_message "Deleted: $filename"
                verbose "Deleted: $filename"
            else
                failed=$((failed + 1))
                log_message "Error: Failed to delete backup: $filename"
                verbose "Error: Failed to delete backup: $filename"
            fi
        done < "$to_delete"
        
        log_message "Autodeletion completed: $deleted deleted, $failed failed, $keep_count kept"
        verbose "Autodeletion completed: $deleted deleted, $failed failed, $keep_count kept"
    fi
    
    # Cleanup
    rm -f "$all_backups" "$keep_backups" "$keep_paths" "$to_delete"
}

###############################################################################
# Main Function
###############################################################################

main() {
    # Set up cleanup trap for temporary files
    # Note: Individual functions handle their own temp file cleanup, but this provides
    # a safety net for script interruption
    # The EXIT trap for logging will be set after validate_destination() when LOG_FILE is available
    trap 'rm -f "${temp_files[@]}" 2>/dev/null; exit' INT TERM
    
    # Parse command line arguments
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    # Check for help
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        usage
        exit 0
    fi
    
    # Get destination (first argument)
    DESTINATION="$1"
    shift
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --include)
                if [ -z "${2:-}" ]; then
                    error_exit "--include requires a path argument"
                fi
                INCLUDE_PATHS+=("$(normalize_path "$2")")
                shift 2
                ;;
            --exclude)
                if [ -z "${2:-}" ]; then
                    error_exit "--exclude requires a path argument"
                fi
                EXCLUDE_PATHS+=("$(normalize_path "$2")")
                shift 2
                ;;
            --paths)
                if [ -z "${2:-}" ]; then
                    error_exit "--paths requires a config file path"
                fi
                PATHS_CONFIG="$2"
                shift 2
                ;;
            --smaller)
                if [ "$SMALLER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --smaller flag multiple times"
                fi
                if [ "$LARGER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --smaller and --larger flags together"
                fi
                SMALLER_FLAG_USED=true
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--smaller requires a size value"
                fi
                # Validate size is a positive number (can be decimal)
                if ! [[ "${2:-}" =~ ^[0-9]+\.?[0-9]*$ ]] || (( $(echo "${2:-} <= 0" | bc -l 2>/dev/null || echo "1") )); then
                    error_exit "--smaller requires a positive number (MB, decimals allowed)"
                fi
                SMALLER_SIZE="$2"
                shift 2
                ;;
            --larger)
                if [ "$LARGER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --larger flag multiple times"
                fi
                if [ "$SMALLER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --larger and --smaller flags together"
                fi
                LARGER_FLAG_USED=true
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--larger requires a size value"
                fi
                # Validate size is a positive number (can be decimal)
                if ! [[ "${2:-}" =~ ^[0-9]+\.?[0-9]*$ ]] || (( $(echo "${2:-} <= 0" | bc -l 2>/dev/null || echo "1") )); then
                    error_exit "--larger requires a positive number (MB, decimals allowed)"
                fi
                LARGER_SIZE="$2"
                shift 2
                ;;
            --newer)
                if [ "$NEWER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --newer flag multiple times"
                fi
                if [ "$OLDER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --newer and --older flags together"
                fi
                NEWER_FLAG_USED=true
                # Check if next argument is a flag (starts with --) or empty
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    # Flag used without value - will use last backup date
                    NEWER_DATE=""
                    shift 1
                else
                    # Check if date format is split across arguments (YYYY-MM-DD HH:MM)
                    if [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "${3:-}" =~ ^[0-9]{2}:[0-9]{2}$ ]] && [[ "${3:-}" != --* ]]; then
                        # Combine date and time
                        NEWER_DATE="$2 $3"
                        shift 3
                    else
                        # Single argument (quoted or days format)
                        NEWER_DATE="$2"
                        shift 2
                    fi
                fi
                ;;
            --older)
                if [ "$OLDER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --older flag multiple times"
                fi
                if [ "$NEWER_FLAG_USED" = true ]; then
                    error_exit "Cannot use --older and --newer flags together"
                fi
                OLDER_FLAG_USED=true
                # Check if next argument is a flag (starts with --) or empty
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    # Flag used without value - error (unlike --newer, --older requires a value)
                    error_exit "--older requires a date or days value"
                else
                    # Check if date format is split across arguments (YYYY-MM-DD HH:MM)
                    if [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "${3:-}" =~ ^[0-9]{2}:[0-9]{2}$ ]] && [[ "${3:-}" != --* ]]; then
                        # Combine date and time
                        OLDER_DATE="$2 $3"
                        shift 3
                    else
                        # Single argument (quoted or days format)
                        OLDER_DATE="$2"
                        shift 2
                    fi
                fi
                ;;
            --keep-last)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--keep-last requires a positive integer value"
                fi
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [ "${2:-}" -le 0 ]; then
                    error_exit "--keep-last requires a positive integer"
                fi
                KEEP_LAST="$2"
                shift 2
                ;;
            --keep-hourly)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--keep-hourly requires a positive integer value"
                fi
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [ "${2:-}" -le 0 ]; then
                    error_exit "--keep-hourly requires a positive integer"
                fi
                KEEP_HOURLY="$2"
                shift 2
                ;;
            --keep-daily)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--keep-daily requires a positive integer value"
                fi
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [ "${2:-}" -le 0 ]; then
                    error_exit "--keep-daily requires a positive integer"
                fi
                KEEP_DAILY="$2"
                shift 2
                ;;
            --keep-weekly)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--keep-weekly requires a positive integer value"
                fi
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [ "${2:-}" -le 0 ]; then
                    error_exit "--keep-weekly requires a positive integer"
                fi
                KEEP_WEEKLY="$2"
                shift 2
                ;;
            --keep-monthly)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--keep-monthly requires a positive integer value"
                fi
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [ "${2:-}" -le 0 ]; then
                    error_exit "--keep-monthly requires a positive integer"
                fi
                KEEP_MONTHLY="$2"
                shift 2
                ;;
            --keep-yearly)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    error_exit "--keep-yearly requires a positive integer value"
                fi
                if ! [[ "${2:-}" =~ ^[0-9]+$ ]] || [ "${2:-}" -le 0 ]; then
                    error_exit "--keep-yearly requires a positive integer"
                fi
                KEEP_YEARLY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --quiet|-q)
                VERBOSE=false
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Check sudo
    check_sudo
    
    # Check dependencies
    check_dependencies
    
    # Validate destination
    validate_destination
    
    # Set up EXIT trap to log end message and cleanup temp files on any exit (after LOG_FILE is set)
    trap 'if [ -n "$LOG_FILE" ]; then log_message "########## Backup script ended ##########"; fi; rm -f "${temp_files[@]}" 2>/dev/null' EXIT
    
    # Start logging - this must be the first log message (after LOG_FILE is set)
    log_message "########## Backup script started ##########"
    
    # Validate mutual exclusivity BEFORE parsing YAML
    # (Check if command-line flags were used with --paths)
    if [ -n "$PATHS_CONFIG" ] && ([ ${#INCLUDE_PATHS[@]} -gt 0 ] || [ ${#EXCLUDE_PATHS[@]} -gt 0 ]); then
        error_exit "Cannot use --paths together with --include or --exclude flags"
    fi
    
    # Parse YAML config if provided
    if [ -n "$PATHS_CONFIG" ]; then
        parse_yaml_config "$PATHS_CONFIG"
    fi
    
    # Validate options (remaining validations)
    validate_options
    
    # Parse date constraints
    if [ "$NEWER_FLAG_USED" = true ]; then
        NEWER_DATE=$(parse_date_value "$NEWER_DATE" "newer")
        if [ -z "$NEWER_DATE" ]; then
            # No previous backup found - ignore the flag
            log_message "No previous backup found, --newer flag ignored (proceeding without time constraint)"
            NEWER_FLAG_USED=false
            NEWER_DATE=""
        else
            # Verify the date can be converted to timestamp
            local test_timestamp=$(date_to_timestamp "$NEWER_DATE")
            if [ "$test_timestamp" = "0" ] || [ -z "$test_timestamp" ]; then
                log_message "Warning: Could not parse date '$NEWER_DATE', --newer flag ignored (proceeding without time constraint)"
                NEWER_FLAG_USED=false
                NEWER_DATE=""
            else
                log_message "Only including files newer than: $NEWER_DATE (timestamp: $test_timestamp)"
            fi
        fi
    fi
    
    if [ "$OLDER_FLAG_USED" = true ]; then
        OLDER_DATE=$(parse_date_value "$OLDER_DATE" "older")
        log_message "Only including files older than: $OLDER_DATE"
    fi
    
    # Log configuration - validate paths and log counts
    local include_count=0
    local exclude_count=0
    
    for path in "${INCLUDE_PATHS[@]}"; do
        if validate_path "$path" "Include"; then
            include_count=$((include_count + 1))
        fi
    done
    
    for path in "${EXCLUDE_PATHS[@]}"; do
        if validate_path "$path" "Exclude"; then
            exclude_count=$((exclude_count + 1))
        fi
    done
    
    log_message "Number of include paths used: ${include_count}"
    log_message "Number of exclude paths used: ${exclude_count}"
    
    if [ -n "$SMALLER_SIZE" ]; then
        log_message "Only including files smaller than ${SMALLER_SIZE} MB"
    fi
    
    if [ -n "$LARGER_SIZE" ]; then
        log_message "Only including files larger than ${LARGER_SIZE} MB"
    fi
    
    # Note: Date constraint messages are already logged above after parsing
    
    # Log retention policies if any are set
    if [ -n "$KEEP_LAST" ] || [ -n "$KEEP_HOURLY" ] || [ -n "$KEEP_DAILY" ] || \
       [ -n "$KEEP_WEEKLY" ] || [ -n "$KEEP_MONTHLY" ] || [ -n "$KEEP_YEARLY" ]; then
        log_message "Retention policies:"
        [ -n "$KEEP_LAST" ] && log_message "  --keep-last: $KEEP_LAST"
        [ -n "$KEEP_HOURLY" ] && log_message "  --keep-hourly: $KEEP_HOURLY"
        [ -n "$KEEP_DAILY" ] && log_message "  --keep-daily: $KEEP_DAILY"
        [ -n "$KEEP_WEEKLY" ] && log_message "  --keep-weekly: $KEEP_WEEKLY"
        [ -n "$KEEP_MONTHLY" ] && log_message "  --keep-monthly: $KEEP_MONTHLY"
        [ -n "$KEEP_YEARLY" ] && log_message "  --keep-yearly: $KEEP_YEARLY"
    fi
    
    log_message "Saving backup in $DESTINATION"
    
    # Create backup
    create_backup
    
    # Apply retention policies and delete old backups (after creating new backup)
    delete_old_backups
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - BACKUP_START_TIME))
    
    if [ "$duration" -eq 0 ]; then
        log_message "Duration: under 1 second"
    else
        log_message "Duration: ${duration} seconds"
    fi
}

# Run main function
main "$@"

# Note: The "ended" message is logged via EXIT trap set in main() after validate_destination()
