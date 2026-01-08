#!/bin/bash

# ============================================================================
# off.sh - Interactive Terminal Menu System
# ============================================================================
# A configurable, interactive terminal menu driven by INI configuration file.
# Requires root/sudo privileges to run.
# ============================================================================

set -euo pipefail

# Configuration file path (fixed)
readonly CONFIG_FILE="/opt/helpers/utils/config/off/settings.ini"

# Terminal state
TERMINAL_RAW_MODE=false
SAVED_STTY=""

# Cleanup function to restore terminal state
cleanup() {
    show_cursor
    if [[ -n "$SAVED_STTY" ]]; then
        stty "$SAVED_STTY" 2>/dev/null || stty sane 2>/dev/null || true
    elif [[ "$TERMINAL_RAW_MODE" == "true" ]]; then
        stty sane 2>/dev/null || true
    fi
}

# Set trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# ============================================================================
# Helper Functions
# ============================================================================

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This program must be run as root."
        exit 1
    fi
}

# Display help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Interactive terminal menu system driven by configuration file.

OPTIONS:
    -h, --help    Show this help message and exit

REQUIREMENTS:
    - Must be run with sudo or as root
    - Configuration file must be created (example file provided in same directory): $CONFIG_FILE
    - Custom script to control menu items must be created (example script is provided as /opt/helpers/utils/scripts/sys-actions.sh.example); default location for custom scripts: /opt/helpers/utils/scripts/custom

FEATURES:
    - Keyboard navigation (↑ ↓ arrows, number keys)
    - Enter key to execute selected item
    - ESC key to exit
    - Configurable menu items via INI file

CONFIGURATION:
    Edit $CONFIG_FILE to configure:
    - Menu items (label, command, enabled status)

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        "")
            # No arguments, continue
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information."
            exit 1
            ;;
    esac
}

# Read INI file and extract values
# Usage: get_ini_value <section> <key> <file>
get_ini_value() {
    local section="$1"
    local key="$2"
    local file="$3"
    
    # Extract value from INI file
    awk -F'=' -v section="$section" -v key="$key" '
        /^\[/ { current_section = substr($0, 2, length($0)-2) }
        current_section == section && $1 == key {
            sub(/^[^=]*=/, "")
            gsub(/^[ \t]+|[ \t]+$/, "")
            print
            exit
        }
    ' "$file" 2>/dev/null || echo ""
}

# Parse menu items from config file
# Populates global arrays: menu_ids, menu_labels, menu_commands
parse_menu_items() {
    local config_file="$1"
    local in_item=false
    local current_id=""
    local current_label=""
    local current_command=""
    local current_enabled=""
    
    menu_ids=()
    menu_labels=()
    menu_commands=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Check for item section
        if [[ "$line" =~ ^\[item\.(.+)\]$ ]]; then
            # Save previous item if enabled
            if [[ "$in_item" == true && "$current_enabled" == "true" ]]; then
                menu_ids+=("$current_id")
                menu_labels+=("$current_label")
                menu_commands+=("$current_command")
            fi
            
            # Start new item
            current_id="${BASH_REMATCH[1]}"
            current_label=""
            current_command=""
            current_enabled=""
            in_item=true
        elif [[ "$line" =~ ^\[.+\]$ ]]; then
            # Other section, close current item
            if [[ "$in_item" == true && "$current_enabled" == "true" ]]; then
                menu_ids+=("$current_id")
                menu_labels+=("$current_label")
                menu_commands+=("$current_command")
            fi
            in_item=false
        elif [[ "$in_item" == true ]]; then
            # Parse item properties
            if [[ "$line" =~ ^label=(.+)$ ]]; then
                current_label="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^command=(.+)$ ]]; then
                current_command="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^enabled=(.+)$ ]]; then
                current_enabled="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$config_file"
    
    # Save last item if enabled
    if [[ "$in_item" == true && "$current_enabled" == "true" ]]; then
        menu_ids+=("$current_id")
        menu_labels+=("$current_label")
        menu_commands+=("$current_command")
    fi
}

# Load configuration from file
load_config() {
    local config_path="$CONFIG_FILE"
    
    if [[ ! -f "$config_path" ]]; then
        echo "Error: Configuration file not found: $config_path"
        exit 1
    fi
    
    # Parse menu items
    parse_menu_items "$config_path"
    
    # Validate we have menu items
    if [[ ${#menu_ids[@]} -eq 0 ]]; then
        echo "Error: No enabled menu items found in configuration"
        exit 1
    fi
}

# ============================================================================
# Terminal UI Functions
# ============================================================================

# Clear screen and hide cursor
clear_screen() {
    printf '\033[2J\033[H'
    printf '\033[?25l'  # Hide cursor
    TERMINAL_RAW_MODE=true
}

# Show cursor
show_cursor() {
    printf '\033[?25h'
}

# Draw menu
draw_menu() {
    local selected=$1
    
    clear_screen
    
    # Title
    printf '\033[1m\033[36m'
    echo "=========================================="
    echo "        SELECT ITEM AND HIT ENTER"
    echo "=========================================="
    printf '\033[0m'
    echo ""
    
    # Menu items
    for i in "${!menu_ids[@]}"; do
        local num=$((i + 1))
        if [[ $i -eq $selected ]]; then
            # Selected item - highlighted
            printf '\033[1m\033[47m\033[30m'
            printf "  %d. %s" "$num" "${menu_labels[$i]}"
            printf '\033[0m'
            echo ""
        else
            # Normal item
            printf "  %d. %s" "$num" "${menu_labels[$i]}"
            echo ""
        fi
    done
    
    echo ""
    
    # Footer
    printf '\033[2m'
    echo "↑ ↓  Enter = Execute   ESC = Exit"
    printf '\033[0m'
}

# ============================================================================
# Input Handling
# ============================================================================

# Read a single character (handles escape sequences)
read_char() {
    local char
    IFS= read -rsn1 char
    
    # Check for escape sequence
    if [[ "$char" == $'\033' ]]; then
        read -rsn1 -t 0.1 char
        if [[ "$char" == '[' ]]; then
            read -rsn1 -t 0.1 char
            case "$char" in
                'A') echo "UP" ;;
                'B') echo "DOWN" ;;
                *) echo "ESC" ;;
            esac
            return
        else
            echo "ESC"
            return
        fi
    fi
    
    # Check for Enter
    if [[ "$char" == "" ]]; then
        echo "ENTER"
        return
    fi
    
    # Check for number keys
    if [[ "$char" =~ [0-9] ]]; then
        echo "NUM:$char"
        return
    fi
    
    # Other character
    echo "$char"
}

# Flush any pending input from terminal buffer
flush_input() {
    # Drain any pending input from stdin
    # This prevents leftover characters from menu navigation from being
    # read by subsequent commands that prompt for user input
    while read -rsn1 -t 0.01 _ 2>/dev/null; do
        : # Discard input
    done
    # Also try to clear using stty if available
    stty flush 2>/dev/null || true
}

# ============================================================================
# Main Menu Loop
# ============================================================================

run_menu() {
    local selected=0
    local input
    
    # Save terminal settings for raw mode (globally for cleanup)
    SAVED_STTY=$(stty -g 2>/dev/null || echo "")
    
    # Set terminal to cbreak mode for better input handling
    # This disables echo and canonical mode
    stty -echo -icanon 2>/dev/null || true
    TERMINAL_RAW_MODE=true
    
    # Initial draw
    draw_menu "$selected"
    
    # Main input loop
    while true; do
        input=$(read_char)
        
        case "$input" in
            "UP")
                selected=$((selected - 1))
                if [[ $selected -lt 0 ]]; then
                    selected=$((${#menu_ids[@]} - 1))
                fi
                draw_menu "$selected"
                ;;
            "DOWN")
                selected=$((selected + 1))
                if [[ $selected -ge ${#menu_ids[@]} ]]; then
                    selected=0
                fi
                draw_menu "$selected"
                ;;
            "ENTER")
                # Restore terminal before executing
                if [[ -n "$SAVED_STTY" ]]; then
                    stty "$SAVED_STTY" 2>/dev/null || stty sane 2>/dev/null || true
                fi
                TERMINAL_RAW_MODE=false
                SAVED_STTY=""
                # Flush any pending input immediately after restoring terminal state
                flush_input
                execute_item "$selected"
                return
                ;;
            "ESC")
                # Restore terminal before exit
                if [[ -n "$SAVED_STTY" ]]; then
                    stty "$SAVED_STTY" 2>/dev/null || stty sane 2>/dev/null || true
                fi
                TERMINAL_RAW_MODE=false
                SAVED_STTY=""
                show_cursor
                clear_screen
                exit 0
                ;;
            NUM:*)
                # Number key pressed
                local num="${input#NUM:}"
                local idx=$((num - 1))
                if [[ $idx -ge 0 && $idx -lt ${#menu_ids[@]} ]]; then
                    selected=$idx
                    draw_menu "$selected"
                fi
                ;;
        esac
    done
}

# Execute menu item
execute_item() {
    local index=$1
    
    show_cursor
    clear_screen
    
    # Flush any pending input from terminal buffer before executing
    # This prevents leftover characters from menu navigation (arrow keys, Enter)
    # from being immediately read by commands that prompt for user input
    flush_input
    
    # Execute the command
    eval "${menu_commands[$index]}"
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    # Parse arguments
    parse_args "${1:-}"
    
    # Check root privileges
    check_root
    
    # Load configuration
    load_config
    
    # Run menu
    run_menu
    
    # Restore cursor
    show_cursor
}

# Run main function
main "$@"
