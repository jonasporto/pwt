#!/bin/bash
# ============================================================
# pwt status module
# Interactive TUI dashboard for monitoring worktrees
# ============================================================
#
# This module is sourced by bin/pwt when the status command is used.
# It provides all TUI-related functions for the status dashboard.
#
# Dependencies:
#   - Requires functions from bin/pwt: get_status_symbols, get_divergence,
#     get_remote_divergence, get_metadata, get_pids_on_port, format_relative_time,
#     load_project_config, etc.
#
# Usage:
#   source "$PWT_LIB/status.sh"
#   cmd_status "$@"
#

# Guard against multiple sourcing
[[ -n "${_PWT_STATUS_LOADED:-}" ]] && return 0
_PWT_STATUS_LOADED=1

# Theme variables (ANSI 16 colors - universal compatibility)
# These are set by load_status_theme()
TH_BORDER=''
TH_BORDER_ACTIVE=''
TH_HEADER=''
TH_TITLE=''
TH_OK=''
TH_WARN=''
TH_ERR=''
TH_INFO=''
TH_SELECTED=''
TH_DIM=''
TH_BOLD=''
TH_RESET=''

# Load theme for status display
load_status_theme() {
    local theme="${PWT_THEME:-default}"
    local theme_file="$PWT_DIR/themes/${theme}.sh"

    if [ -f "$theme_file" ]; then
        # shellcheck source=/dev/null
        source "$theme_file"
    else
        # Default theme (ANSI 16 colors)
        TH_BORDER='\033[2m'           # Dim - box borders
        TH_BORDER_ACTIVE='\033[1;36m' # Bold cyan - active pane
        TH_HEADER='\033[1;37m'        # Bold white - headers
        TH_TITLE='\033[1;33m'         # Bold yellow - titles
        TH_OK='\033[32m'              # Green - clean/running
        TH_WARN='\033[33m'            # Yellow - changes/warning
        TH_ERR='\033[31m'             # Red - error/conflict
        TH_INFO='\033[36m'            # Cyan - info
        TH_SELECTED='\033[7m'         # Reverse - selected row
        TH_DIM='\033[2m'              # Dim - secondary info
        TH_BOLD='\033[1m'             # Bold - emphasis
        TH_RESET='\033[0m'            # Reset
    fi
}

# Status TUI state variables
declare -a STATUS_WORKTREES=()      # Worktree names
declare -a STATUS_BRANCHES=()       # Branch names
declare -a STATUS_STATUSES=()       # Git status symbols
declare -a STATUS_PORTS=()          # Port numbers
declare -a STATUS_SERVER_STATUS=()  # Server running state
declare -a STATUS_MAIN_DIV=()       # Divergence from main
declare -a STATUS_REMOTE_DIV=()     # Divergence from remote
declare -a STATUS_AGES=()           # Last commit age
declare -a STATUS_PATHS=()          # Full paths
declare -a STATUS_ACTIVITY=()       # Activity log entries

# View navigation state
STATUS_VIEW="project"           # Current view: global, project, worktree
STATUS_SELECTED_PROJECT=""      # Selected project name (for global view navigation)
STATUS_SELECTED_WORKTREE=""     # Selected worktree name (for worktree view)

# Pane state
STATUS_PANE=0           # Current active pane (0=worktrees, 1=details, 2=servers, 3=activity)
STATUS_SELECTED=0       # Selected item in current pane
STATUS_SERVER_SELECTED=0  # Selected item in servers pane
STATUS_SCROLL=0         # Scroll offset for worktrees pane
STATUS_SERVER_SCROLL=0  # Scroll offset for servers pane
STATUS_ACTIVITY_SCROLL=0  # Scroll offset for activity pane
STATUS_TERM_WIDTH=80    # Terminal width
STATUS_TERM_HEIGHT=24   # Terminal height
STATUS_REFRESH_INTERVAL=2  # Refresh interval in seconds
STATUS_LAST_REFRESH=0   # Last refresh timestamp
STATUS_RUNNING=true     # Main loop control
STATUS_SHOW_HELP=false  # Show help overlay
STATUS_NEEDS_CLEAR=false  # Flag to trigger full screen clear (on view change, resize, etc.)
STATUS_FILTER=""        # Filter string
STATUS_SHOW_ALL=false   # Show all projects (--all flag)

# Global view state (list of all projects)
declare -a STATUS_PROJECTS=()        # Project names
declare -a STATUS_PROJECT_PATHS=()   # Project paths
declare -a STATUS_PROJECT_WT_COUNT=()  # Worktree count per project
declare -a STATUS_PROJECT_DIRTY=()   # Dirty worktree count per project
declare -a STATUS_PROJECT_SERVERS=() # Running server count per project
STATUS_PROJECT_SELECTED=0            # Selected project in global view
STATUS_PROJECT_SCROLL=0              # Scroll offset for global view

# Spinners for loading animation
STATUS_SPINNERS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
STATUS_SPINNER_IDX=0

# Initialize TUI (alternate screen, hide cursor, setup trap)
status_init() {
    # Save terminal state and switch to alternate screen
    tput smcup 2>/dev/null || true
    # Hide cursor
    tput civis 2>/dev/null || true
    # Enable keypad mode for arrow keys
    tput smkx 2>/dev/null || true
    # Reset scroll region (ensure full screen is usable)
    printf '\033[r' 2>/dev/null || true
    # Clear screen once at start
    tput clear 2>/dev/null || true
    # Position cursor at top-left
    tput cup 0 0 2>/dev/null || true

    # Get terminal dimensions - try multiple methods
    status_update_terminal_size

    # Setup cleanup trap
    trap status_cleanup EXIT INT TERM
    # Handle terminal resize
    trap 'STATUS_NEEDS_CLEAR=true; status_update_terminal_size' WINCH

    # Load theme
    load_status_theme

    # Initial data collection based on view
    if [ "$STATUS_VIEW" = "global" ]; then
        status_collect_global_data
    else
        status_collect_data
    fi
}

# Cleanup TUI (restore terminal)
status_cleanup() {
    # Show cursor
    tput cnorm 2>/dev/null || true
    # Disable keypad mode
    tput rmkx 2>/dev/null || true
    # Switch back from alternate screen
    tput rmcup 2>/dev/null || true
    # Reset colors
    echo -ne '\033[0m'

    # Remove traps
    trap - EXIT INT TERM WINCH
}

# Read a single key with timeout (non-blocking)
# Returns the key in STATUS_KEY variable
status_read_key() {
    STATUS_KEY=""
    local key=""
    local escape_seq=""

    # Read single character with timeout from /dev/tty
    if IFS= read -rsn1 -t 0.5 key </dev/tty 2>/dev/null; then
        # Check for escape sequences (arrow keys, etc.)
        if [[ "$key" == $'\e' ]]; then
            # Read up to 2 more characters for escape sequence with short timeout
            if IFS= read -rsn1 -t 0.1 escape_seq </dev/tty 2>/dev/null; then
                if [[ "$escape_seq" == "[" ]] || [[ "$escape_seq" == "O" ]]; then
                    local third=""
                    if IFS= read -rsn1 -t 0.1 third </dev/tty 2>/dev/null; then
                        case "${escape_seq}${third}" in
                            '[A'|'OA') STATUS_KEY="UP" ;;
                            '[B'|'OB') STATUS_KEY="DOWN" ;;
                            '[C'|'OC') STATUS_KEY="RIGHT" ;;
                            '[D'|'OD') STATUS_KEY="LEFT" ;;
                            '[Z')      STATUS_KEY="SHIFT_TAB" ;;
                            *)         STATUS_KEY="ESC" ;;
                        esac
                    else
                        STATUS_KEY="ESC"
                    fi
                else
                    STATUS_KEY="ESC"
                fi
            else
                STATUS_KEY="ESC"
            fi
        else
            STATUS_KEY="$key"
        fi
        return 0
    fi
    return 1
}

# Collect data for all worktrees
status_collect_data() {
    # Clear arrays
    STATUS_WORKTREES=()
    STATUS_BRANCHES=()
    STATUS_STATUSES=()
    STATUS_PORTS=()
    STATUS_SERVER_STATUS=()
    STATUS_MAIN_DIV=()
    STATUS_REMOTE_DIV=()
    STATUS_AGES=()
    STATUS_PATHS=()

    # Add main app first
    if [ -d "$MAIN_APP" ]; then
        STATUS_WORKTREES+=("@")
        STATUS_BRANCHES+=("$(git -C "$MAIN_APP" branch --show-current 2>/dev/null || echo "?")")
        STATUS_STATUSES+=("$(get_status_symbols "$MAIN_APP")")
        STATUS_PORTS+=("${BASE_PORT:-5000}")
        STATUS_PATHS+=("$MAIN_APP")

        # Check if server is running on main port
        local main_port="${BASE_PORT:-5000}"
        local main_pids=$(get_pids_on_port "$main_port" 2>/dev/null || true)
        if [ -n "$main_pids" ]; then
            STATUS_SERVER_STATUS+=("RUNNING")
        else
            STATUS_SERVER_STATUS+=("STOPPED")
        fi

        STATUS_MAIN_DIV+=("")
        STATUS_REMOTE_DIV+=("$(get_remote_divergence "$MAIN_APP")")

        local age_ts=$(git -C "$MAIN_APP" log -1 --format=%ct 2>/dev/null || echo "0")
        STATUS_AGES+=("$(format_relative_time "$age_ts")")
    fi

    # Add worktrees
    if [ -d "$WORKTREES_DIR" ]; then
        for dir in "$WORKTREES_DIR"/*/; do
            [ -d "$dir" ] || continue
            local name=$(basename "$dir")
            local path="${dir%/}"

            STATUS_WORKTREES+=("$name")
            STATUS_BRANCHES+=("$(git -C "$path" branch --show-current 2>/dev/null || echo "detached")")
            STATUS_STATUSES+=("$(get_status_symbols "$path")")
            STATUS_PATHS+=("$path")

            # Get port from metadata
            local port=$(get_metadata "$name" "port" 2>/dev/null || echo "")
            STATUS_PORTS+=("$port")

            # Check if server is running
            if [ -n "$port" ]; then
                local pids=$(get_pids_on_port "$port" 2>/dev/null || true)
                if [ -n "$pids" ]; then
                    STATUS_SERVER_STATUS+=("RUNNING")
                else
                    STATUS_SERVER_STATUS+=("STOPPED")
                fi
            else
                STATUS_SERVER_STATUS+=("")
            fi

            # Divergence
            STATUS_MAIN_DIV+=("$(get_divergence "$path" "origin/${DEFAULT_BRANCH:-master}" 2>/dev/null || echo "")")
            STATUS_REMOTE_DIV+=("$(get_remote_divergence "$path" 2>/dev/null || echo "")")

            # Age
            local age_ts=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo "0")
            STATUS_AGES+=("$(format_relative_time "$age_ts")")
        done
    fi
}

# Collect data for all projects (global view)
status_collect_global_data() {
    # Clear arrays
    STATUS_PROJECTS=()
    STATUS_PROJECT_PATHS=()
    STATUS_PROJECT_WT_COUNT=()
    STATUS_PROJECT_DIRTY=()
    STATUS_PROJECT_SERVERS=()

    # Iterate over all configured projects
    if [ -d "$PWT_PROJECTS_DIR" ]; then
        for project_dir in "$PWT_PROJECTS_DIR"/*/; do
            [ -d "$project_dir" ] || continue
            local project_name=$(basename "$project_dir")
            local config_file="$project_dir/config.json"
            [ -f "$config_file" ] || continue

            STATUS_PROJECTS+=("$project_name")

            # Get project path
            local main_app=$(jq -r '.path // .main_app // empty' "$config_file" 2>/dev/null)
            STATUS_PROJECT_PATHS+=("${main_app:-}")

            # Get worktrees directory
            local worktrees_dir=$(jq -r '.worktrees_dir // empty' "$config_file" 2>/dev/null)

            # Count worktrees
            local wt_count=0
            local dirty_count=0
            local server_count=0

            if [ -n "$worktrees_dir" ] && [ -d "$worktrees_dir" ]; then
                for wt_dir in "$worktrees_dir"/*/; do
                    [ -d "$wt_dir" ] || continue
                    wt_count=$((wt_count + 1))

                    # Check dirty status
                    local status=$(get_status_symbols "$wt_dir" 2>/dev/null)
                    [ -n "$status" ] && dirty_count=$((dirty_count + 1))
                done
            fi

            # Check running servers from metadata
            if [ -f "$PWT_META_FILE" ]; then
                local ports=$(jq -r --arg proj "$project_name" '.[$proj] // {} | to_entries[] | .value.port // empty' "$PWT_META_FILE" 2>/dev/null)
                for port in $ports; do
                    if [ -n "$port" ]; then
                        local pids=$(get_pids_on_port "$port" 2>/dev/null || true)
                        [ -n "$pids" ] && server_count=$((server_count + 1))
                    fi
                done
            fi

            STATUS_PROJECT_WT_COUNT+=("$wt_count")
            STATUS_PROJECT_DIRTY+=("$dirty_count")
            STATUS_PROJECT_SERVERS+=("$server_count")
        done
    fi
}

# Navigate into a project (global -> project view)
status_drill_down_project() {
    if [ "$STATUS_VIEW" = "global" ]; then
        local selected_project="${STATUS_PROJECTS[$STATUS_PROJECT_SELECTED]:-}"
        if [ -n "$selected_project" ]; then
            STATUS_SELECTED_PROJECT="$selected_project"
            STATUS_VIEW="project"
            STATUS_NEEDS_CLEAR=true  # Clear screen on view change

            # Load project config (suppress any errors to prevent exit)
            if ! load_project_config "$selected_project" 2>/dev/null; then
                status_add_activity "Warning: Could not load config for $selected_project"
            fi
            CURRENT_PROJECT="$selected_project"

            # Reset project view state
            STATUS_SELECTED=0
            STATUS_SCROLL=0
            STATUS_PANE=0

            # Collect project data (suppress errors)
            status_collect_data 2>/dev/null || true
            status_add_activity "Entered project: $selected_project"
        fi
    fi
}

# Navigate into a worktree (project -> worktree view)
status_drill_down_worktree() {
    if [ "$STATUS_VIEW" = "project" ]; then
        local selected_wt="${STATUS_WORKTREES[$STATUS_SELECTED]:-}"
        if [ -n "$selected_wt" ]; then
            STATUS_SELECTED_WORKTREE="$selected_wt"
            STATUS_VIEW="worktree"
            STATUS_NEEDS_CLEAR=true  # Clear screen on view change
            STATUS_PANE=0
            status_add_activity "Viewing worktree: $selected_wt"
        fi
    fi
}

# Navigate back one level
status_nav_back() {
    STATUS_NEEDS_CLEAR=true  # Clear screen on view change
    case "$STATUS_VIEW" in
        worktree)
            STATUS_VIEW="project"
            STATUS_SELECTED_WORKTREE=""
            STATUS_PANE=0
            ;;
        project)
            if [ "$STATUS_SHOW_ALL" = true ]; then
                STATUS_VIEW="global"
                STATUS_SELECTED_PROJECT=""
                STATUS_PANE=0
                status_collect_global_data
            fi
            ;;
        global)
            # Already at top level, do nothing or exit
            ;;
    esac
}

# Get breadcrumb string for current view
status_get_breadcrumb() {
    case "$STATUS_VIEW" in
        global)
            echo "All Projects"
            ;;
        project)
            if [ "$STATUS_SHOW_ALL" = true ]; then
                echo "All Projects > ${STATUS_SELECTED_PROJECT:-$CURRENT_PROJECT}"
            else
                echo "${CURRENT_PROJECT:-unknown}"
            fi
            ;;
        worktree)
            if [ "$STATUS_SHOW_ALL" = true ]; then
                echo "All Projects > ${STATUS_SELECTED_PROJECT:-$CURRENT_PROJECT} > ${STATUS_SELECTED_WORKTREE:-}"
            else
                echo "${CURRENT_PROJECT:-unknown} > ${STATUS_SELECTED_WORKTREE:-}"
            fi
            ;;
    esac
}

# Add activity log entry
status_add_activity() {
    local message="$1"
    local timestamp=$(date +%H:%M)
    local worktree="${STATUS_WORKTREES[$STATUS_SELECTED]:-}"

    # Prepend to activity array (newest first)
    STATUS_ACTIVITY=("$timestamp $worktree $message" "${STATUS_ACTIVITY[@]}")

    # Keep only last 50 entries
    if [ ${#STATUS_ACTIVITY[@]} -gt 50 ]; then
        STATUS_ACTIVITY=("${STATUS_ACTIVITY[@]:0:50}")
    fi
}

# Draw a horizontal line
status_update_terminal_size() {
    local width=0 height=0

    # Check if /dev/tty is available
    local use_tty=false
    if [ -c /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
        use_tty=true
    fi

    # Method 1: Use stty size (most reliable for actual terminal)
    if $use_tty; then
        local stty_size
        stty_size=$(stty size 2>/dev/null </dev/tty) || stty_size=""
        if [ -n "$stty_size" ]; then
            height=${stty_size%% *}
            width=${stty_size##* }
        fi
    fi

    # Method 2: Use tput
    if [ "$width" -le 0 ] 2>/dev/null || [ -z "$width" ]; then
        if $use_tty; then
            width=$(tput cols 2>/dev/null </dev/tty) || width=0
            height=$(tput lines 2>/dev/null </dev/tty) || height=0
        else
            width=$(tput cols 2>/dev/null) || width=0
            height=$(tput lines 2>/dev/null) || height=0
        fi
    fi

    # Method 3: Query terminal using escape sequence (only if tty available)
    if [ "$width" -le 0 ] 2>/dev/null || [ -z "$width" ]; then
        if $use_tty; then
            # Save cursor, move to 999,999, get position, restore cursor
            local pos
            printf '\033[s\033[999;999H\033[6n\033[u' >/dev/tty 2>/dev/null
            IFS=';' read -t 1 -s -d 'R' -r _ pos </dev/tty 2>/dev/null
            if [ -n "$pos" ]; then
                width=${pos##*;}
                height=${pos%%;*}
                height=${height#*[}
            fi
        fi
    fi

    # Method 4: Use COLUMNS/LINES environment variables (often set by shell)
    if [ "$width" -le 0 ] 2>/dev/null || [ -z "$width" ]; then
        # Force bash to update COLUMNS/LINES
        shopt -s checkwinsize 2>/dev/null
        (:)  # Subshell triggers checkwinsize
        width=${COLUMNS:-80}
        height=${LINES:-24}
    fi

    # Fallback to defaults
    [ -z "$width" ] || [ "$width" -le 0 ] 2>/dev/null && width=80
    [ -z "$height" ] || [ "$height" -le 0 ] 2>/dev/null && height=24

    # Ensure minimum values
    [ "$width" -lt 60 ] && width=60
    [ "$height" -lt 15 ] && height=15

    STATUS_TERM_WIDTH=$width
    STATUS_TERM_HEIGHT=$height
}

status_draw_hline() {
    local width="$1"
    local char="${2:-─}"
    local i
    for ((i=0; i<width; i++)); do
        printf "%s" "$char"
    done
}

# Draw outer frame borders for all content rows (just the edges, no clearing)
status_render_frame() {
    local start_row=3
    local end_row=$((STATUS_TERM_HEIGHT - 3))

    echo -ne "$TH_HEADER"
    for ((row=start_row; row<=end_row; row++)); do
        tput cup $row 0
        printf "║"
        tput cup $row $((STATUS_TERM_WIDTH - 1))
        printf "║"
    done
    echo -ne "$TH_RESET"
}

# Draw box border top
status_draw_box_top() {
    local width="$1"
    local title="$2"
    local active="${3:-false}"

    if [ "$active" = true ]; then
        echo -ne "$TH_BORDER_ACTIVE"
    else
        echo -ne "$TH_BORDER"
    fi

    printf "┌─"
    if [ -n "$title" ]; then
        printf " %s " "$title"
        local title_len=$((${#title} + 4))
        status_draw_hline $((width - title_len - 3))
    else
        status_draw_hline $((width - 4))
    fi
    printf "─┐"
    echo -ne "$TH_RESET"
}

# Draw box border bottom
status_draw_box_bottom() {
    local width="$1"
    local active="${2:-false}"

    if [ "$active" = true ]; then
        echo -ne "$TH_BORDER_ACTIVE"
    else
        echo -ne "$TH_BORDER"
    fi

    printf "└"
    status_draw_hline $((width - 2))
    printf "┘"
    echo -ne "$TH_RESET"
}

# Render header bar
status_render_header() {
    local time_str=$(date +%H:%M:%S)
    local breadcrumb=$(status_get_breadcrumb)
    local spinner="${STATUS_SPINNERS[$STATUS_SPINNER_IDX]}"

    # Advance spinner
    STATUS_SPINNER_IDX=$(( (STATUS_SPINNER_IDX + 1) % ${#STATUS_SPINNERS[@]} ))

    # Move to top
    tput cup 0 0

    echo -ne "$TH_HEADER"
    printf "╔"
    status_draw_hline $((STATUS_TERM_WIDTH - 2)) "═"
    printf "╗"
    echo -ne "$TH_RESET"

    tput cup 1 0
    echo -ne "$TH_HEADER"
    printf "║  "
    echo -ne "$TH_TITLE"
    printf "⚡ PWT STATUS"
    echo -ne "$TH_RESET$TH_HEADER"
    printf " ══ "
    echo -ne "$TH_INFO"
    printf "%s" "$breadcrumb"
    echo -ne "$TH_RESET$TH_HEADER"

    # Right side: spinner and time
    local left_content="  ⚡ PWT STATUS ══ $breadcrumb"
    local right_content="$spinner $time_str  "
    local padding=$((STATUS_TERM_WIDTH - ${#left_content} - ${#right_content} - 2))
    [ $padding -lt 0 ] && padding=0

    printf "%*s" "$padding" ""
    echo -ne "$TH_DIM"
    printf "%s %s" "$spinner" "$time_str"
    echo -ne "$TH_RESET$TH_HEADER"
    printf "  ║"
    echo -ne "$TH_RESET"

    tput cup 2 0
    echo -ne "$TH_HEADER"
    printf "╠"
    status_draw_hline $((STATUS_TERM_WIDTH - 2)) "═"
    printf "╣"
    echo -ne "$TH_RESET"
}

# Render worktrees pane (left side)
status_render_pane_worktrees() {
    local start_row=3
    local start_col=1  # After outer frame
    local content_width=$((STATUS_TERM_WIDTH - 2))  # Between outer frames
    local pane_width=$(( content_width * 2 / 3 ))
    local pane_height=$((STATUS_TERM_HEIGHT - 10))
    local is_active=$([[ $STATUS_PANE -eq 0 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "WORKTREES" "$is_active"

    local visible_rows=$((pane_height - 2))
    local total_items=${#STATUS_WORKTREES[@]}

    # Adjust scroll to keep selected visible
    if [ $STATUS_SELECTED -lt $STATUS_SCROLL ]; then
        STATUS_SCROLL=$STATUS_SELECTED
    elif [ $STATUS_SELECTED -ge $((STATUS_SCROLL + visible_rows)) ]; then
        STATUS_SCROLL=$((STATUS_SELECTED - visible_rows + 1))
    fi

    local row=0
    for ((i=STATUS_SCROLL; i < STATUS_SCROLL + visible_rows && i < total_items; i++)); do
        tput cup $((start_row + 1 + row)) $start_col

        local name="${STATUS_WORKTREES[$i]}"
        local branch="${STATUS_BRANCHES[$i]}"
        local status="${STATUS_STATUSES[$i]}"
        local port="${STATUS_PORTS[$i]}"
        local server="${STATUS_SERVER_STATUS[$i]}"
        local main_div="${STATUS_MAIN_DIV[$i]}"
        local remote_div="${STATUS_REMOTE_DIV[$i]}"

        # Build marker
        local marker=" "
        local path="${STATUS_PATHS[$i]}"
        if [ "$PWD" = "$path" ]; then
            marker="@"
        elif is_previous_worktree "$path" 2>/dev/null; then
            marker="*"
        fi

        # Selection highlight
        if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
            echo -ne "$TH_SELECTED"
            printf "│▶"
        else
            echo -ne "$TH_BORDER"
            printf "│"
            echo -ne "$TH_RESET"
            printf " "
        fi

        # Marker
        if [ "$marker" = "@" ]; then
            echo -ne "$TH_INFO"
        elif [ "$marker" = "*" ]; then
            echo -ne "$TH_DIM"
        fi
        printf "%s " "$marker"
        echo -ne "$TH_RESET"

        # Name (with selection if active)
        if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi
        printf "%-15s " "${name:0:15}"

        # Status symbols
        if [ -n "$status" ]; then
            echo -ne "$TH_WARN"
        else
            echo -ne "$TH_OK"
            status="✓"
        fi
        printf "%-4s" "$status"
        echo -ne "$TH_RESET"

        # Server status icon
        if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi
        if [ -n "$port" ]; then
            if [ "$server" = "RUNNING" ]; then
                echo -ne "$TH_OK"
                printf "▶"
            else
                echo -ne "$TH_DIM"
                printf "◼"
            fi
            echo -ne "$TH_RESET"
            if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
                echo -ne "$TH_SELECTED"
            fi
            printf ":%-5s" "$port"
        else
            printf "  -    "
        fi
        echo -ne "$TH_RESET"

        # Divergence
        if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi
        if [ -n "$main_div" ]; then
            echo -ne "$TH_INFO"
            printf "%-8s" "${main_div:0:8}"
        else
            printf "%-8s" ""
        fi
        echo -ne "$TH_RESET"

        # Remote divergence
        if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi
        if [ -n "$remote_div" ]; then
            echo -ne "$TH_WARN"
            printf "%-6s" "${remote_div:0:6}"
        else
            printf "%-6s" ""
        fi
        echo -ne "$TH_RESET"

        # Fill remaining space
        local content_len=$((2 + 2 + 16 + 4 + 7 + 8 + 6))
        local remaining=$((pane_width - content_len - 1))
        if [ "$is_active" = true ] && [ $i -eq $STATUS_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi
        printf "%*s" "$remaining" ""
        echo -ne "$TH_RESET"

        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"

        row=$((row + 1))
    done

    # Fill empty rows
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + 1 + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        printf "%*s" $((pane_width - 2)) ""
        printf "│"
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    # Scrollbar indicator
    if [ $total_items -gt $visible_rows ]; then
        local scrollbar_pos=$((start_row + 1 + (STATUS_SCROLL * visible_rows / total_items)))
        tput cup $scrollbar_pos $((start_col + pane_width - 1))
        echo -ne "$TH_INFO"
        printf "▓"
        echo -ne "$TH_RESET"
    fi

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render details pane (right side)
status_render_pane_details() {
    local start_row=3
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local left_pane_width=$(( content_width * 2 / 3 ))
    local start_col=$((1 + left_pane_width))
    local pane_width=$((content_width - left_pane_width))
    local pane_height=$((STATUS_TERM_HEIGHT - 10))
    local is_active=$([[ $STATUS_PANE -eq 1 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "DETAILS" "$is_active"

    # Get selected worktree info
    local idx=$STATUS_SELECTED
    local name="${STATUS_WORKTREES[$idx]:-}"
    local branch="${STATUS_BRANCHES[$idx]:-}"
    local status="${STATUS_STATUSES[$idx]:-}"
    local port="${STATUS_PORTS[$idx]:-}"
    local server="${STATUS_SERVER_STATUS[$idx]:-}"
    local path="${STATUS_PATHS[$idx]:-}"
    local age="${STATUS_AGES[$idx]:-}"

    local row=1

    # Selected worktree name
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    printf " "
    echo -ne "$TH_TITLE"
    printf "▶ %s" "${name:-none}"
    echo -ne "$TH_RESET"
    printf "%*s" $((pane_width - ${#name} - 5)) ""
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Empty line
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│%*s│" $((pane_width - 2)) ""
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Branch
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Branch:"
    echo -ne "$TH_RESET"
    printf " %-*s" $((pane_width - 11)) "${branch:0:$((pane_width - 12))}"
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Status
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Status:"
    echo -ne "$TH_RESET"
    if [ -n "$status" ]; then
        # Parse status symbols
        local staged=0 modified=0 untracked=0
        [[ "$status" == *"+"* ]] && staged=1
        [[ "$status" == *"!"* ]] && modified=1
        [[ "$status" == *"?"* ]] && untracked=1

        local status_str=""
        [ $staged -eq 1 ] && status_str="${status_str}+staged "
        [ $modified -eq 1 ] && status_str="${status_str}!modified "
        [ $untracked -eq 1 ] && status_str="${status_str}?untracked"

        echo -ne "$TH_WARN"
        printf " %-*s" $((pane_width - 11)) "$status_str"
    else
        echo -ne "$TH_OK"
        printf " %-*s" $((pane_width - 11)) "✓ clean"
    fi
    echo -ne "$TH_RESET$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Server info
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Server:"
    echo -ne "$TH_RESET"
    if [ -n "$port" ]; then
        if [ "$server" = "RUNNING" ]; then
            echo -ne "$TH_OK"
            printf " ▶ :%-5s RUNNING" "$port"
        else
            echo -ne "$TH_DIM"
            printf " ◼ :%-5s STOPPED" "$port"
        fi
        printf "%*s" $((pane_width - 26)) ""
    else
        printf " %-*s" $((pane_width - 11)) "-"
    fi
    echo -ne "$TH_RESET$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Last activity
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Last:"
    echo -ne "$TH_RESET"
    printf " %-*s" $((pane_width - 9)) "${age:-?} ago"
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Path
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Path:"
    echo -ne "$TH_RESET"
    # Truncate path if too long
    local max_path=$((pane_width - 10))
    local display_path="$path"
    if [ ${#path} -gt $max_path ]; then
        display_path="...${path: -$((max_path - 3))}"
    fi
    printf " %-*s" $((pane_width - 9)) "$display_path"
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Fill remaining rows
    local visible_rows=$((pane_height - 2))
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render servers pane (bottom left)
status_render_pane_servers() {
    local worktrees_height=$((STATUS_TERM_HEIGHT - 10))
    local start_row=$((3 + worktrees_height))
    local start_col=1
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local pane_width=$(( content_width * 2 / 3 ))
    local pane_height=5
    local is_active=$([[ $STATUS_PANE -eq 2 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "SERVERS" "$is_active"

    local row=0
    local visible_rows=$((pane_height - 2))

    # Collect servers with ports
    local server_indices=()
    for ((i=0; i<${#STATUS_WORKTREES[@]}; i++)); do
        if [ -n "${STATUS_PORTS[$i]}" ]; then
            server_indices+=($i)
        fi
    done

    # Adjust scroll
    local total_servers=${#server_indices[@]}
    if [ $STATUS_SERVER_SELECTED -lt $STATUS_SERVER_SCROLL ]; then
        STATUS_SERVER_SCROLL=$STATUS_SERVER_SELECTED
    elif [ $STATUS_SERVER_SELECTED -ge $((STATUS_SERVER_SCROLL + visible_rows)) ]; then
        STATUS_SERVER_SCROLL=$((STATUS_SERVER_SELECTED - visible_rows + 1))
    fi

    for ((si=STATUS_SERVER_SCROLL; si < STATUS_SERVER_SCROLL + visible_rows && si < total_servers; si++)); do
        local i=${server_indices[$si]}
        local name="${STATUS_WORKTREES[$i]}"
        local port="${STATUS_PORTS[$i]}"
        local server="${STATUS_SERVER_STATUS[$i]}"

        tput cup $((start_row + 1 + row)) $start_col

        if [ "$is_active" = true ] && [ $si -eq $STATUS_SERVER_SELECTED ]; then
            echo -ne "$TH_SELECTED"
            printf "│▶"
        else
            echo -ne "$TH_BORDER"
            printf "│ "
            echo -ne "$TH_RESET"
        fi

        # Port
        echo -ne "$TH_INFO"
        printf ":%-5s" "$port"
        echo -ne "$TH_RESET"

        if [ "$is_active" = true ] && [ $si -eq $STATUS_SERVER_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi

        # Worktree name
        printf " %-12s " "${name:0:12}"

        # Status
        if [ "$server" = "RUNNING" ]; then
            echo -ne "$TH_OK"
            printf "▶ RUNNING "
        else
            echo -ne "$TH_DIM"
            printf "◼ STOPPED "
        fi
        echo -ne "$TH_RESET"

        if [ "$is_active" = true ] && [ $si -eq $STATUS_SERVER_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi

        # PID if running
        if [ "$server" = "RUNNING" ]; then
            local pids=$(get_pids_on_port "$port" 2>/dev/null | head -1)
            printf "PID %-6s" "${pids:-?}"
        else
            printf "%10s" ""
        fi

        # Fill remaining
        local content_len=$((2 + 6 + 13 + 10 + 10))
        local remaining=$((pane_width - content_len - 1))
        printf "%*s" "$remaining" ""
        echo -ne "$TH_RESET$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"

        row=$((row + 1))
    done

    # Fill empty rows
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + 1 + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render activity pane (bottom right)
status_render_pane_activity() {
    local worktrees_height=$((STATUS_TERM_HEIGHT - 10))
    local start_row=$((3 + worktrees_height))
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local left_pane_width=$(( content_width * 2 / 3 ))
    local start_col=$((1 + left_pane_width))
    local pane_width=$((content_width - left_pane_width))
    local pane_height=5
    local is_active=$([[ $STATUS_PANE -eq 3 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "ACTIVITY" "$is_active"

    local row=0
    local visible_rows=$((pane_height - 2))
    local total_activities=${#STATUS_ACTIVITY[@]}

    for ((i=STATUS_ACTIVITY_SCROLL; i < STATUS_ACTIVITY_SCROLL + visible_rows && i < total_activities; i++)); do
        local entry="${STATUS_ACTIVITY[$i]}"

        tput cup $((start_row + 1 + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"

        echo -ne "$TH_DIM"
        printf " ░ "
        echo -ne "$TH_RESET"

        # Truncate entry to fit
        local max_len=$((pane_width - 6))
        printf "%-*s" "$max_len" "${entry:0:$max_len}"

        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"

        row=$((row + 1))
    done

    # Fill empty rows or show placeholder
    if [ $total_activities -eq 0 ] && [ $row -eq 0 ]; then
        tput cup $((start_row + 1)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_DIM"
        printf " (no recent activity)"
        printf "%*s" $((pane_width - 23)) ""
        echo -ne "$TH_RESET$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"
        row=1
    fi

    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + 1 + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render footer with keyboard shortcuts
status_render_footer() {
    local start_row=$((STATUS_TERM_HEIGHT - 2))

    tput cup $start_row 0
    echo -ne "$TH_HEADER"
    printf "╠"
    status_draw_hline $((STATUS_TERM_WIDTH - 2)) "═"
    printf "╣"
    echo -ne "$TH_RESET"

    tput cup $((start_row + 1)) 0
    echo -ne "$TH_HEADER"
    printf "║"
    echo -ne "$TH_RESET"

    # Shortcuts
    echo -ne "$TH_INFO"
    printf " [Tab]"
    echo -ne "$TH_DIM"
    printf "pane"

    echo -ne "$TH_INFO"
    printf " [q]"
    echo -ne "$TH_DIM"
    printf "uit"

    echo -ne "$TH_INFO"
    printf " [↑↓]"
    echo -ne "$TH_DIM"
    printf "nav"

    echo -ne "$TH_INFO"
    printf " [Enter]"
    echo -ne "$TH_DIM"
    printf "cd"

    echo -ne "$TH_INFO"
    printf " [s]"
    echo -ne "$TH_DIM"
    printf "erver"

    echo -ne "$TH_INFO"
    printf " [p]"
    echo -ne "$TH_DIM"
    printf "ull"

    echo -ne "$TH_INFO"
    printf " [P]"
    echo -ne "$TH_DIM"
    printf "ush"

    echo -ne "$TH_INFO"
    printf " [d]"
    echo -ne "$TH_DIM"
    printf "iff"

    echo -ne "$TH_INFO"
    printf " [r]"
    echo -ne "$TH_DIM"
    printf "efresh"

    echo -ne "$TH_INFO"
    printf " [?]"
    echo -ne "$TH_DIM"
    printf "help"
    echo -ne "$TH_RESET"

    # Fill to end of line and close
    local shortcuts_len=90  # approximate
    local remaining=$((STATUS_TERM_WIDTH - shortcuts_len - 2))
    [ $remaining -lt 0 ] && remaining=0
    printf "%*s" "$remaining" ""
    echo -ne "$TH_HEADER"
    printf "║"
    tput el  # Clear to end of line
    echo -ne "$TH_RESET"

    tput cup $((STATUS_TERM_HEIGHT - 1)) 0
    echo -ne "$TH_HEADER"
    printf "╚"
    status_draw_hline $((STATUS_TERM_WIDTH - 2)) "═"
    printf "╝"
    tput el  # Clear to end of line
    echo -ne "$TH_RESET"
}

# Render help overlay
status_render_help() {
    local help_width=50
    local help_height=20
    local start_col=$(( (STATUS_TERM_WIDTH - help_width) / 2 ))
    local start_row=$(( (STATUS_TERM_HEIGHT - help_height) / 2 ))

    # Draw help box
    tput cup $start_row $start_col
    echo -ne "$TH_BORDER_ACTIVE"
    printf "╔"
    status_draw_hline $((help_width - 2)) "═"
    printf "╗"

    local help_lines=(
        ""
        "  KEYBOARD SHORTCUTS"
        ""
        "  Navigation:"
        "    Tab/Shift+Tab    Switch panes"
        "    ↑/k  ↓/j         Move up/down"
        "    1-4              Jump to pane"
        ""
        "  Actions:"
        "    Enter            cd to selected worktree"
        "    s                Toggle server start/stop"
        "    p                Git pull"
        "    P                Git push"
        "    d                Show git diff"
        "    f                Git fetch"
        "    r                Force refresh"
        ""
        "    q/Esc            Quit"
        ""
    )

    for ((i=0; i<${#help_lines[@]}; i++)); do
        tput cup $((start_row + 1 + i)) $start_col
        printf "║"
        printf "%-*s" $((help_width - 2)) "${help_lines[$i]}"
        printf "║"
    done

    tput cup $((start_row + help_height - 1)) $start_col
    printf "╚"
    status_draw_hline $((help_width - 2)) "═"
    printf "╝"
    echo -ne "$TH_RESET"
}

# Render projects pane for global view (left side)
status_render_pane_projects() {
    local start_row=3
    local start_col=1
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local pane_width=$(( content_width * 2 / 3 ))
    local pane_height=$((STATUS_TERM_HEIGHT - 7))
    local is_active=$([[ $STATUS_PANE -eq 0 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "PROJECTS" "$is_active"

    local visible_rows=$((pane_height - 2))
    local total_items=${#STATUS_PROJECTS[@]}

    # Adjust scroll to keep selected visible
    if [ $STATUS_PROJECT_SELECTED -lt $STATUS_PROJECT_SCROLL ]; then
        STATUS_PROJECT_SCROLL=$STATUS_PROJECT_SELECTED
    elif [ $STATUS_PROJECT_SELECTED -ge $((STATUS_PROJECT_SCROLL + visible_rows)) ]; then
        STATUS_PROJECT_SCROLL=$((STATUS_PROJECT_SELECTED - visible_rows + 1))
    fi

    local row=0
    for ((i=STATUS_PROJECT_SCROLL; i < STATUS_PROJECT_SCROLL + visible_rows && i < total_items; i++)); do
        tput cup $((start_row + 1 + row)) $start_col

        local name="${STATUS_PROJECTS[$i]}"
        local path="${STATUS_PROJECT_PATHS[$i]}"
        local wt_count="${STATUS_PROJECT_WT_COUNT[$i]}"
        local dirty="${STATUS_PROJECT_DIRTY[$i]}"
        local servers="${STATUS_PROJECT_SERVERS[$i]}"

        # Selection highlight
        if [ "$is_active" = true ] && [ $i -eq $STATUS_PROJECT_SELECTED ]; then
            echo -ne "$TH_SELECTED"
            printf "│▶ "
        else
            echo -ne "$TH_BORDER"
            printf "│"
            echo -ne "$TH_RESET"
            printf "  "
        fi

        # Project name
        if [ "$is_active" = true ] && [ $i -eq $STATUS_PROJECT_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi
        echo -ne "$TH_TITLE"
        printf "%-20s" "${name:0:20}"
        echo -ne "$TH_RESET"

        if [ "$is_active" = true ] && [ $i -eq $STATUS_PROJECT_SELECTED ]; then
            echo -ne "$TH_SELECTED"
        fi

        # Worktree count
        printf " %2d wt" "$wt_count"

        # Dirty count
        if [ "$dirty" -gt 0 ]; then
            echo -ne "$TH_WARN"
            printf "  !%d dirty" "$dirty"
            echo -ne "$TH_RESET"
            if [ "$is_active" = true ] && [ $i -eq $STATUS_PROJECT_SELECTED ]; then
                echo -ne "$TH_SELECTED"
            fi
        else
            printf "         "
        fi

        # Server count
        if [ "$servers" -gt 0 ]; then
            echo -ne "$TH_OK"
            printf "  ▶%d" "$servers"
            echo -ne "$TH_RESET"
            if [ "$is_active" = true ] && [ $i -eq $STATUS_PROJECT_SELECTED ]; then
                echo -ne "$TH_SELECTED"
            fi
        else
            printf "    "
        fi

        # Fill remaining space
        local content_len=$((3 + 20 + 6 + 10 + 4))
        local remaining=$((pane_width - content_len - 1))
        [ $remaining -lt 0 ] && remaining=0
        printf "%*s" "$remaining" ""
        echo -ne "$TH_RESET$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"

        row=$((row + 1))
    done

    # Fill empty rows
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + 1 + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        printf "%*s" $((pane_width - 2)) ""
        printf "│"
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render project details pane for global view (right side)
status_render_pane_project_details() {
    local start_row=3
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local left_pane_width=$(( content_width * 2 / 3 ))
    local start_col=$((1 + left_pane_width))
    local pane_width=$((content_width - left_pane_width))
    local pane_height=$((STATUS_TERM_HEIGHT - 7))
    local is_active=$([[ $STATUS_PANE -eq 1 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "PROJECT DETAILS" "$is_active"

    # Get selected project info
    local idx=$STATUS_PROJECT_SELECTED
    local name="${STATUS_PROJECTS[$idx]:-}"
    local path="${STATUS_PROJECT_PATHS[$idx]:-}"
    local wt_count="${STATUS_PROJECT_WT_COUNT[$idx]:-0}"
    local dirty="${STATUS_PROJECT_DIRTY[$idx]:-0}"
    local servers="${STATUS_PROJECT_SERVERS[$idx]:-0}"

    local row=1

    # Project name
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    printf " "
    echo -ne "$TH_TITLE"
    printf "▶ %s" "${name:-none}"
    echo -ne "$TH_RESET"
    printf "%*s" $((pane_width - ${#name} - 5)) ""
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Empty line
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│%*s│" $((pane_width - 2)) ""
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Path
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Path:"
    echo -ne "$TH_RESET"
    local max_path=$((pane_width - 10))
    local display_path="$path"
    if [ ${#path} -gt $max_path ]; then
        display_path="...${path: -$((max_path - 3))}"
    fi
    printf " %-*s" $((pane_width - 9)) "$display_path"
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Worktrees
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Worktrees:"
    echo -ne "$TH_RESET"
    printf " %-*s" $((pane_width - 14)) "$wt_count"
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Dirty
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Dirty:"
    echo -ne "$TH_RESET"
    if [ "$dirty" -gt 0 ]; then
        echo -ne "$TH_WARN"
        printf " %-*s" $((pane_width - 10)) "$dirty"
        echo -ne "$TH_RESET"
    else
        echo -ne "$TH_OK"
        printf " %-*s" $((pane_width - 10)) "0 (clean)"
        echo -ne "$TH_RESET"
    fi
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Servers
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Servers:"
    echo -ne "$TH_RESET"
    if [ "$servers" -gt 0 ]; then
        echo -ne "$TH_OK"
        printf " %d running" "$servers"
    else
        printf " none"
    fi
    printf "%*s" $((pane_width - 20)) ""
    echo -ne "$TH_RESET$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Fill remaining rows
    local visible_rows=$((pane_height - 2))
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Worktree view data
declare -a STATUS_WT_FILES=()        # Modified files list
declare -a STATUS_WT_COMMITS=()      # Recent commits
declare -a STATUS_WT_STASHES=()      # Stash list
STATUS_WT_STAGED=0                   # Staged file count
STATUS_WT_MODIFIED=0                 # Modified file count
STATUS_WT_UNTRACKED=0                # Untracked file count

# Collect detailed worktree data for worktree view
status_collect_worktree_data() {
    local idx=$STATUS_SELECTED
    local path="${STATUS_PATHS[$idx]:-}"

    [ -z "$path" ] || [ ! -d "$path" ] && return

    # Clear arrays
    STATUS_WT_FILES=()
    STATUS_WT_COMMITS=()
    STATUS_WT_STASHES=()

    # Get detailed file status
    STATUS_WT_STAGED=$(git -C "$path" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    STATUS_WT_MODIFIED=$(git -C "$path" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    STATUS_WT_UNTRACKED=$(git -C "$path" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    # Get modified files (limited to 20)
    while IFS= read -r file; do
        [ -n "$file" ] && STATUS_WT_FILES+=("M $file")
    done < <(git -C "$path" diff --name-only 2>/dev/null | head -20)

    # Get staged files
    while IFS= read -r file; do
        [ -n "$file" ] && STATUS_WT_FILES+=("+ $file")
    done < <(git -C "$path" diff --cached --name-only 2>/dev/null | head -10)

    # Get untracked files
    while IFS= read -r file; do
        [ -n "$file" ] && STATUS_WT_FILES+=("? $file")
    done < <(git -C "$path" ls-files --others --exclude-standard 2>/dev/null | head -10)

    # Get recent commits (last 10)
    while IFS= read -r commit; do
        [ -n "$commit" ] && STATUS_WT_COMMITS+=("$commit")
    done < <(git -C "$path" log --oneline -10 2>/dev/null)

    # Get stashes
    while IFS= read -r stash; do
        [ -n "$stash" ] && STATUS_WT_STASHES+=("$stash")
    done < <(git -C "$path" stash list 2>/dev/null | head -5)
}

# Render git status pane for worktree view (left)
status_render_pane_git_status() {
    local start_row=3
    local start_col=1
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local pane_width=$(( content_width * 2 / 3 ))
    local pane_height=$(( (STATUS_TERM_HEIGHT - 10) / 2 ))
    local is_active=$([[ $STATUS_PANE -eq 0 ]] && echo true || echo false)

    tput cup $start_row $start_col
    local wt="${STATUS_SELECTED_WORKTREE:-?}"
    status_draw_box_top "$pane_width" "GIT STATUS: $wt" "$is_active"

    local row=1
    local visible_rows=$((pane_height - 2))

    # Summary line
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    printf " "

    if [ $STATUS_WT_STAGED -gt 0 ]; then
        echo -ne "$TH_OK"
        printf "+%d staged  " "$STATUS_WT_STAGED"
        echo -ne "$TH_RESET"
    fi
    if [ $STATUS_WT_MODIFIED -gt 0 ]; then
        echo -ne "$TH_WARN"
        printf "!%d modified  " "$STATUS_WT_MODIFIED"
        echo -ne "$TH_RESET"
    fi
    if [ $STATUS_WT_UNTRACKED -gt 0 ]; then
        echo -ne "$TH_DIM"
        printf "?%d untracked" "$STATUS_WT_UNTRACKED"
        echo -ne "$TH_RESET"
    fi
    if [ $STATUS_WT_STAGED -eq 0 ] && [ $STATUS_WT_MODIFIED -eq 0 ] && [ $STATUS_WT_UNTRACKED -eq 0 ]; then
        echo -ne "$TH_OK"
        printf "✓ Clean"
        echo -ne "$TH_RESET"
    fi

    local remaining=$((pane_width - 50))
    [ $remaining -lt 0 ] && remaining=0
    printf "%*s" "$remaining" ""
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Separator
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "├"
    status_draw_hline $((pane_width - 2))
    printf "┤"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # File list
    local file_count=${#STATUS_WT_FILES[@]}
    for ((i=0; i < visible_rows - 3 && i < file_count; i++)); do
        local file="${STATUS_WT_FILES[$i]}"
        local prefix="${file:0:1}"
        local name="${file:2}"

        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"
        printf " "

        case "$prefix" in
            "+") echo -ne "$TH_OK" ;;
            "M") echo -ne "$TH_WARN" ;;
            "?") echo -ne "$TH_DIM" ;;
        esac
        printf "%s " "$prefix"
        echo -ne "$TH_RESET"

        local max_name=$((pane_width - 6))
        printf "%-*s" "$max_name" "${name:0:$max_name}"
        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    # Fill remaining rows
    while [ $row -lt $((visible_rows)) ]; do
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render recent commits pane for worktree view (right)
status_render_pane_commits() {
    local start_row=3
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local left_pane_width=$(( content_width * 2 / 3 ))
    local start_col=$((1 + left_pane_width))
    local pane_width=$((content_width - left_pane_width))
    local pane_height=$(( (STATUS_TERM_HEIGHT - 10) / 2 ))
    local is_active=$([[ $STATUS_PANE -eq 1 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "RECENT COMMITS" "$is_active"

    local row=1
    local visible_rows=$((pane_height - 2))
    local commit_count=${#STATUS_WT_COMMITS[@]}

    for ((i=0; i < visible_rows && i < commit_count; i++)); do
        local commit="${STATUS_WT_COMMITS[$i]}"

        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"

        # Hash (first 7 chars)
        echo -ne "$TH_INFO"
        printf " %.7s " "${commit%% *}"
        echo -ne "$TH_RESET"

        # Message
        local msg="${commit#* }"
        local max_msg=$((pane_width - 12))
        printf "%-*s" "$max_msg" "${msg:0:$max_msg}"

        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    # Fill empty rows
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render stashes pane for worktree view (bottom left)
status_render_pane_stashes() {
    local git_height=$(( (STATUS_TERM_HEIGHT - 10) / 2 ))
    local start_row=$((3 + git_height))
    local start_col=1
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local pane_width=$(( content_width * 2 / 3 ))
    local pane_height=$((STATUS_TERM_HEIGHT - start_row - 4))
    local is_active=$([[ $STATUS_PANE -eq 2 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "STASHES" "$is_active"

    local row=1
    local visible_rows=$((pane_height - 2))
    local stash_count=${#STATUS_WT_STASHES[@]}

    if [ $stash_count -eq 0 ]; then
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│"
        echo -ne "$TH_DIM"
        printf " (no stashes)"
        printf "%*s" $((pane_width - 15)) ""
        echo -ne "$TH_RESET$TH_BORDER"
        printf "│"
        echo -ne "$TH_RESET"
        row=$((row + 1))
    else
        for ((i=0; i < visible_rows && i < stash_count; i++)); do
            local stash="${STATUS_WT_STASHES[$i]}"

            tput cup $((start_row + row)) $start_col
            echo -ne "$TH_BORDER"
            printf "│"
            echo -ne "$TH_RESET"

            local max_stash=$((pane_width - 4))
            printf " %-*s" "$max_stash" "${stash:0:$max_stash}"

            echo -ne "$TH_BORDER"
            printf "│"
            echo -ne "$TH_RESET"
            row=$((row + 1))
        done
    fi

    # Fill empty rows
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Render worktree info pane for worktree view (bottom right)
status_render_pane_worktree_info() {
    local git_height=$(( (STATUS_TERM_HEIGHT - 10) / 2 ))
    local start_row=$((3 + git_height))
    local content_width=$((STATUS_TERM_WIDTH - 2))
    local left_pane_width=$(( content_width * 2 / 3 ))
    local start_col=$((1 + left_pane_width))
    local pane_width=$((content_width - left_pane_width))
    local pane_height=$((STATUS_TERM_HEIGHT - start_row - 4))
    local is_active=$([[ $STATUS_PANE -eq 3 ]] && echo true || echo false)

    tput cup $start_row $start_col
    status_draw_box_top "$pane_width" "WORKTREE INFO" "$is_active"

    local idx=$STATUS_SELECTED
    local name="${STATUS_WORKTREES[$idx]:-}"
    local branch="${STATUS_BRANCHES[$idx]:-}"
    local port="${STATUS_PORTS[$idx]:-}"
    local server="${STATUS_SERVER_STATUS[$idx]:-}"
    local path="${STATUS_PATHS[$idx]:-}"
    local age="${STATUS_AGES[$idx]:-}"

    local row=1
    local visible_rows=$((pane_height - 2))

    # Branch
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Branch: "
    echo -ne "$TH_RESET$TH_INFO"
    printf "%-*s" $((pane_width - 12)) "${branch:0:$((pane_width - 13))}"
    echo -ne "$TH_RESET$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Server
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Server: "
    echo -ne "$TH_RESET"
    if [ -n "$port" ]; then
        if [ "$server" = "RUNNING" ]; then
            echo -ne "$TH_OK"
            printf "▶ :%s RUNNING" "$port"
        else
            echo -ne "$TH_DIM"
            printf "◼ :%s STOPPED" "$port"
        fi
    else
        printf "-"
    fi
    printf "%*s" $((pane_width - 25)) ""
    echo -ne "$TH_RESET$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Last activity
    tput cup $((start_row + row)) $start_col
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET$TH_DIM"
    printf " Last:   "
    echo -ne "$TH_RESET"
    printf "%-*s" $((pane_width - 12)) "${age:-?} ago"
    echo -ne "$TH_BORDER"
    printf "│"
    echo -ne "$TH_RESET"
    row=$((row + 1))

    # Fill remaining rows
    while [ $row -lt $visible_rows ]; do
        tput cup $((start_row + row)) $start_col
        echo -ne "$TH_BORDER"
        printf "│%*s│" $((pane_width - 2)) ""
        echo -ne "$TH_RESET"
        row=$((row + 1))
    done

    tput cup $((start_row + pane_height - 1)) $start_col
    status_draw_box_bottom "$pane_width" "$is_active"
}

# Main render function
status_render() {
    # Check if terminal was resized
    local old_width=$STATUS_TERM_WIDTH
    local old_height=$STATUS_TERM_HEIGHT
    status_update_terminal_size
    if [ "$old_width" != "$STATUS_TERM_WIDTH" ] || [ "$old_height" != "$STATUS_TERM_HEIGHT" ]; then
        STATUS_NEEDS_CLEAR=true
    fi

    # Clear screen if needed (view change, resize, help toggle)
    if [ "$STATUS_NEEDS_CLEAR" = true ]; then
        # Reset scroll region and clear completely
        printf '\033[r' 2>/dev/null || true
        tput clear 2>/dev/null || true
        tput cup 0 0 2>/dev/null || true
        STATUS_NEEDS_CLEAR=false
    fi

    # Move cursor to top-left
    tput cup 0 0 2>/dev/null || true

    # Minimum size check
    if [ $STATUS_TERM_WIDTH -lt 60 ] || [ $STATUS_TERM_HEIGHT -lt 15 ]; then
        tput cup 0 0
        echo "Terminal too small. Minimum: 60x15"
        return
    fi

    status_render_header
    status_render_frame  # Draw outer frame borders

    # Render panes based on current view
    case "$STATUS_VIEW" in
        global)
            status_render_pane_projects
            status_render_pane_project_details
            # No servers/activity panes in global view - simpler layout
            ;;
        project)
            status_render_pane_worktrees
            status_render_pane_details
            status_render_pane_servers
            status_render_pane_activity
            ;;
        worktree)
            # Detailed worktree view with git status, commits, stashes
            status_collect_worktree_data
            status_render_pane_git_status
            status_render_pane_commits
            status_render_pane_stashes
            status_render_pane_worktree_info
            ;;
    esac

    status_render_footer

    if [ "$STATUS_SHOW_HELP" = true ]; then
        status_render_help
    fi

    # Position cursor at safe location to prevent any stray output
    tput cup 0 $((STATUS_TERM_WIDTH - 1)) 2>/dev/null || true
}

# Handle navigation
status_nav_up() {
    case "$STATUS_VIEW" in
        global)
            case $STATUS_PANE in
                0) # Projects pane
                    if [ $STATUS_PROJECT_SELECTED -gt 0 ]; then
                        STATUS_PROJECT_SELECTED=$((STATUS_PROJECT_SELECTED - 1))
                    fi
                    ;;
            esac
            ;;
        project|worktree)
            case $STATUS_PANE in
                0) # Worktrees pane
                    if [ $STATUS_SELECTED -gt 0 ]; then
                        STATUS_SELECTED=$((STATUS_SELECTED - 1))
                    fi
                    ;;
                2) # Servers pane
                    if [ $STATUS_SERVER_SELECTED -gt 0 ]; then
                        STATUS_SERVER_SELECTED=$((STATUS_SERVER_SELECTED - 1))
                    fi
                    ;;
                3) # Activity pane
                    if [ $STATUS_ACTIVITY_SCROLL -gt 0 ]; then
                        STATUS_ACTIVITY_SCROLL=$((STATUS_ACTIVITY_SCROLL - 1))
                    fi
                    ;;
            esac
            ;;
    esac
}

status_nav_down() {
    case "$STATUS_VIEW" in
        global)
            case $STATUS_PANE in
                0) # Projects pane
                    local max=$((${#STATUS_PROJECTS[@]} - 1))
                    if [ $STATUS_PROJECT_SELECTED -lt $max ]; then
                        STATUS_PROJECT_SELECTED=$((STATUS_PROJECT_SELECTED + 1))
                    fi
                    ;;
            esac
            ;;
        project|worktree)
            case $STATUS_PANE in
                0) # Worktrees pane
                    local max=$((${#STATUS_WORKTREES[@]} - 1))
                    if [ $STATUS_SELECTED -lt $max ]; then
                        STATUS_SELECTED=$((STATUS_SELECTED + 1))
                    fi
                    ;;
                2) # Servers pane
                    # Count servers
                    local count=0
                    for port in "${STATUS_PORTS[@]}"; do
                        [ -n "$port" ] && count=$((count + 1))
                    done
                    local max=$((count - 1))
                    if [ $STATUS_SERVER_SELECTED -lt $max ]; then
                        STATUS_SERVER_SELECTED=$((STATUS_SERVER_SELECTED + 1))
                    fi
                    ;;
                3) # Activity pane
                    local max=$((${#STATUS_ACTIVITY[@]} - 3))
                    [ $max -lt 0 ] && max=0
                    if [ $STATUS_ACTIVITY_SCROLL -lt $max ]; then
                        STATUS_ACTIVITY_SCROLL=$((STATUS_ACTIVITY_SCROLL + 1))
                    fi
                    ;;
            esac
            ;;
    esac
}

status_nav_pane_next() {
    case "$STATUS_VIEW" in
        global)
            # Global view only has 2 panes
            STATUS_PANE=$(( (STATUS_PANE + 1) % 2 ))
            ;;
        *)
            STATUS_PANE=$(( (STATUS_PANE + 1) % 4 ))
            ;;
    esac
}

status_nav_pane_prev() {
    case "$STATUS_VIEW" in
        global)
            # Global view only has 2 panes
            STATUS_PANE=$(( (STATUS_PANE + 1) % 2 ))
            ;;
        *)
            STATUS_PANE=$(( (STATUS_PANE + 3) % 4 ))
            ;;
    esac
}

# Action: cd to selected worktree
status_action_cd() {
    local path="${STATUS_PATHS[$STATUS_SELECTED]}"
    if [ -n "$path" ] && [ -d "$path" ]; then
        # Cleanup and print cd command for shell integration
        status_cleanup
        echo "cd $path"
        exit 0
    fi
}

# Action: toggle server
status_action_toggle_server() {
    local idx=$STATUS_SELECTED
    if [ $STATUS_PANE -eq 2 ]; then
        # In servers pane, use server selection
        local count=0
        for ((i=0; i<${#STATUS_PORTS[@]}; i++)); do
            if [ -n "${STATUS_PORTS[$i]}" ]; then
                if [ $count -eq $STATUS_SERVER_SELECTED ]; then
                    idx=$i
                    break
                fi
                count=$((count + 1))
            fi
        done
    fi

    local name="${STATUS_WORKTREES[$idx]}"
    local port="${STATUS_PORTS[$idx]}"
    local server="${STATUS_SERVER_STATUS[$idx]}"
    local path="${STATUS_PATHS[$idx]}"

    if [ -z "$port" ]; then
        status_add_activity "No port configured"
        return
    fi

    if [ "$server" = "RUNNING" ]; then
        # Stop server
        local pids=$(get_pids_on_port "$port" 2>/dev/null)
        if [ -n "$pids" ]; then
            echo "$pids" | xargs kill 2>/dev/null || true
            status_add_activity "Server stopped :$port"
            STATUS_SERVER_STATUS[$idx]="STOPPED"
        fi
    else
        # Start server - this needs to run in background
        status_add_activity "Starting server :$port..."

        # Export environment and run Pwtfile server command
        (
            cd "$path" || exit 1
            export PWT_PORT="$port"
            export PWT_WORKTREE="$name"
            export PWT_WORKTREE_PATH="$path"
            export PORT="$port"

            # Try to run Pwtfile server command
            if has_pwtfile_command "server" 2>/dev/null; then
                run_pwtfile "server" &
            fi
        ) &>/dev/null &

        # Give it a moment to start
        sleep 1
        status_collect_data  # Refresh to get new status
    fi
}

# Action: git pull
status_action_git_pull() {
    local path="${STATUS_PATHS[$STATUS_SELECTED]}"
    local name="${STATUS_WORKTREES[$STATUS_SELECTED]}"

    if [ -n "$path" ] && [ -d "$path" ]; then
        status_add_activity "git pull..."
        git -C "$path" pull --quiet 2>/dev/null && \
            status_add_activity "pull completed" || \
            status_add_activity "pull failed"
        status_collect_data
    fi
}

# Action: git push
status_action_git_push() {
    local path="${STATUS_PATHS[$STATUS_SELECTED]}"
    local name="${STATUS_WORKTREES[$STATUS_SELECTED]}"

    if [ -n "$path" ] && [ -d "$path" ]; then
        status_add_activity "git push..."
        git -C "$path" push --quiet 2>/dev/null && \
            status_add_activity "push completed" || \
            status_add_activity "push failed"
        status_collect_data
    fi
}

# Action: show diff
status_action_show_diff() {
    local path="${STATUS_PATHS[$STATUS_SELECTED]}"

    if [ -n "$path" ] && [ -d "$path" ]; then
        # Temporarily exit TUI to show diff
        status_cleanup

        echo -e "${BLUE}Git diff for: ${STATUS_WORKTREES[$STATUS_SELECTED]}${NC}"
        echo ""
        git -C "$path" diff --stat
        echo ""
        echo -e "${DIM}Press Enter to return to status...${NC}"
        read -r

        # Re-initialize TUI
        status_init
    fi
}

# Action: git fetch
status_action_git_fetch() {
    status_add_activity "git fetch --all..."
    for path in "${STATUS_PATHS[@]}"; do
        if [ -d "$path" ]; then
            git -C "$path" fetch --quiet 2>/dev/null || true
        fi
    done
    status_add_activity "fetch completed"
    status_collect_data
}

# Handle keyboard input
status_handle_key() {
    local key="$1"

    # Debug mode: log key to activity
    if [ "${PWT_DEBUG:-}" = "1" ]; then
        local key_display="$key"
        case "$key" in
            $'\n') key_display="NEWLINE" ;;
            $'\r') key_display="CR" ;;
            $'\t') key_display="TAB" ;;
            $'\e') key_display="ESC_CHAR" ;;
            "") key_display="EMPTY" ;;
            " ") key_display="SPACE" ;;
        esac
        status_add_activity "KEY: [$key_display] VIEW: $STATUS_VIEW PANE: $STATUS_PANE"
    fi

    # Help mode toggle
    if [ "$STATUS_SHOW_HELP" = true ]; then
        STATUS_SHOW_HELP=false
        STATUS_NEEDS_CLEAR=true  # Clear after closing help
        return
    fi

    case "$key" in
        q|Q)
            STATUS_RUNNING=false
            ;;
        ESC)
            # Navigate back or quit if at top level
            if [ "$STATUS_VIEW" = "global" ]; then
                STATUS_RUNNING=false
            elif [ "$STATUS_VIEW" = "project" ] && [ "$STATUS_SHOW_ALL" != true ]; then
                STATUS_RUNNING=false
            else
                status_nav_back
            fi
            ;;
        $'\x7f'|LEFT|h)  # Backspace, Left arrow, or h
            # Navigate back one level
            if [ "$STATUS_VIEW" != "global" ]; then
                if [ "$STATUS_VIEW" = "project" ] && [ "$STATUS_SHOW_ALL" != true ]; then
                    # At project level without --all, just exit
                    :
                else
                    status_nav_back
                fi
            fi
            ;;
        "?")
            STATUS_SHOW_HELP=true
            STATUS_NEEDS_CLEAR=true  # Clear to show help overlay
            ;;
        UP|k)
            status_nav_up
            ;;
        DOWN|j)
            status_nav_down
            ;;
        $'\t') # Tab
            status_nav_pane_next
            ;;
        SHIFT_TAB)
            status_nav_pane_prev
            ;;
        1)
            STATUS_PANE=0
            ;;
        2)
            STATUS_PANE=1
            ;;
        3)
            STATUS_PANE=2
            ;;
        4)
            STATUS_PANE=3
            ;;
        ""|" "|$'\n'|$'\r'|RIGHT|l)  # Enter, Space, Newline, CR, Right arrow, or l
            # Drill down or action based on current view and pane
            case "$STATUS_VIEW" in
                global)
                    # Drill down into selected project
                    status_drill_down_project
                    ;;
                project)
                    if [ $STATUS_PANE -eq 0 ]; then
                        # Drill down into selected worktree
                        status_drill_down_worktree
                    else
                        # On other panes, do cd action
                        status_action_cd
                    fi
                    ;;
                worktree)
                    # In worktree view, cd to the worktree
                    status_action_cd
                    ;;
            esac
            ;;
        c)
            # Quick cd and exit (always)
            status_action_cd
            ;;
        s)
            status_action_toggle_server
            ;;
        p)
            status_action_git_pull
            ;;
        P)
            status_action_git_push
            ;;
        d)
            status_action_show_diff
            ;;
        f)
            status_action_git_fetch
            ;;
        r|R)
            # Refresh based on current view
            if [ "$STATUS_VIEW" = "global" ]; then
                status_collect_global_data
            else
                status_collect_data
            fi
            status_add_activity "Refreshed"
            ;;
    esac
}

# Main status command
cmd_status() {
    local show_all=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                echo "Usage: pwt status [options]"
                echo ""
                echo "Interactive TUI dashboard for monitoring worktrees."
                echo ""
                echo "Options:"
                echo "  --all, -a     Show all projects (global view)"
                echo "  --help, -h    Show this help"
                echo ""
                echo "Views:"
                echo "  Global        All projects (with --all flag)"
                echo "  Project       Worktrees for current project (default)"
                echo "  Worktree      Details for a single worktree"
                echo ""
                echo "Navigation:"
                echo "  Tab           Switch between panes"
                echo "  ↑/k ↓/j       Navigate up/down"
                echo "  Enter/→/l     Drill down into selection"
                echo "  Esc/←/h       Go back up one level"
                echo "  1-4           Jump to pane"
                echo ""
                echo "Actions:"
                echo "  c             cd to selected worktree and exit"
                echo "  s             Toggle server start/stop"
                echo "  p             Git pull"
                echo "  P             Git push"
                echo "  d             Show git diff"
                echo "  f             Git fetch all"
                echo "  r             Force refresh data"
                echo "  q             Quit"
                echo ""
                echo "Theme:"
                echo "  Set PWT_THEME environment variable to use custom theme."
                echo "  Themes are stored in ~/.pwt/themes/<name>.sh"
                return 0
                ;;
            -a|--all)
                show_all=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    STATUS_SHOW_ALL=$show_all

    # Set initial view based on flags
    if [ "$show_all" = true ]; then
        STATUS_VIEW="global"
        STATUS_SELECTED_PROJECT=""
    else
        STATUS_VIEW="project"
        STATUS_SELECTED_PROJECT="$CURRENT_PROJECT"
    fi

    # Initialize TUI
    status_init

    # Initial render
    status_render

    # Main event loop
    while [ "$STATUS_RUNNING" = true ]; do
        local now=$(date +%s)

        # Auto-refresh every N seconds based on current view
        if (( now - STATUS_LAST_REFRESH >= STATUS_REFRESH_INTERVAL )); then
            if [ "$STATUS_VIEW" = "global" ]; then
                status_collect_global_data 2>/dev/null || true
            else
                status_collect_data 2>/dev/null || true
            fi
            STATUS_LAST_REFRESH=$now
        fi

        # Render (suppress any stray output)
        status_render 2>/dev/null

        # Handle input
        if status_read_key; then
            status_handle_key "$STATUS_KEY" 2>/dev/null || true
        fi
    done

    # Cleanup
    status_cleanup
}
