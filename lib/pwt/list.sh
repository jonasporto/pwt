#!/bin/bash
# ============================================================
# pwt list module
# Worktree listing and tree display
# ============================================================
#
# This module is sourced by bin/pwt for list/tree commands.
#
# Dependencies:
#   - Requires functions from bin/pwt: init_metadata, get_metadata, has_lsof,
#     get_pids_on_port, get_status_symbols, get_divergence, get_remote_divergence,
#     format_relative_time, run_pwtfile, has_pwtfile
#   - Requires variables: MAIN_APP, WORKTREES_DIR, CURRENT_PROJECT, DEFAULT_BRANCH,
#     LIST_CACHE_DIR, LIST_CACHE_TTL, LIST_QUICK_MODE, PREFETCH_DONE,
#     RED, GREEN, BLUE, YELLOW, CYAN, DIM, NC
#

# Guard against multiple sourcing
[[ -n "${_PWT_LIST_LOADED:-}" ]] && return 0
_PWT_LIST_LOADED=1

# Note: Cache functions (init_cache_dir, clear_list_cache, etc.) are in bin/pwt
# as they're shared infrastructure used by multiple modules.

# ============================================
# List helper functions
# ============================================

# Check port status for a worktree
# Arguments: port [worktree_dir]
# Returns: colored text with status
check_port_status() {
    local port="$1"
    local worktree_dir="${2:-}"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}[port ?]${NC}"
        return
    fi

    # Without lsof, we can't check port status
    if ! has_lsof; then
        echo -e "${YELLOW}[port $port]${NC}"
        return
    fi

    local pids=$(get_pids_on_port "$port")

    # If no port occupied, it's free
    if [ -z "$pids" ]; then
        echo -e "${GREEN}[port $port free]${NC}"
        return
    fi

    # Port is in use - get process info
    local first_pid=$(echo "$pids" | head -1)
    local proc=$(ps -p "$first_pid" -o comm= 2>/dev/null || echo "?")
    local proc_path=$(ps -p "$first_pid" -o command= 2>/dev/null || echo "")

    # Filter out known system processes (not dev servers)
    # These commonly bind to ports but aren't related to development
    local is_system_process=false
    case "$proc" in
        ControlCenter|controlcenter|rapportd|AirPlayXPCHelper|sharingd)
            is_system_process=true
            ;;
    esac
    # Also check if it's a system path
    if [[ "$proc_path" == /System/* ]] || [[ "$proc_path" == /usr/libexec/* ]]; then
        is_system_process=true
    fi

    if [ "$is_system_process" = true ]; then
        # System process on this port - treat as if port is available for dev
        echo -e "${YELLOW}[port $port: system]${NC}"
    else
        echo -e "${GREEN}[port $port: $proc]${NC}"
    fi
}

# Prefetch remote refs once (for list performance)
# Call this before looping through worktrees
prefetch_remote_refs() {
    if [ "$LIST_QUICK_MODE" = true ]; then
        return 0  # Skip in quick mode
    fi
    if [ "$PREFETCH_DONE" = true ]; then
        return 0  # Already fetched
    fi
    if [ ! -d "$MAIN_APP" ]; then
        return 0  # No main app
    fi

    cd "$MAIN_APP"
    # Fetch only default branch (faster than --prune which fetches all)
    local target="${DEFAULT_BRANCH:-master}"
    git fetch origin "$target" --quiet 2>/dev/null || true
    PREFETCH_DONE=true
}

# Check if branch is merged into master
# IMPORTANT: Also checks for uncommitted changes to avoid data loss
check_merge_status() {
    local dir="$1"
    local target="${2:-master}"
    local wt_commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null)

    if [ -z "$wt_commit" ]; then
        echo -e "${RED}[corrupted]${NC}"
        return
    fi

    # Check for uncommitted changes (staged, modified, or untracked)
    local has_changes=false
    local git_status=$(git -C "$dir" status --porcelain 2>/dev/null)
    if [ -n "$git_status" ]; then
        has_changes=true
    fi

    # If there are uncommitted changes, ALWAYS show as open (unsafe to remove)
    if [ "$has_changes" = true ]; then
        echo -e "${YELLOW}[has changes]${NC}"
        return
    fi

    # Note: Assumes prefetch_remote_refs() was called before the loop
    # (performance: fetch once instead of per-worktree)
    cd "$MAIN_APP"

    if git merge-base --is-ancestor "$wt_commit" "origin/$target" 2>/dev/null; then
        # Check if branch ever diverged from target
        # If merge-base equals HEAD, branch never had unique commits
        local merge_base=$(git -C "$dir" merge-base HEAD "origin/$target" 2>/dev/null)
        if [ "$merge_base" = "$wt_commit" ]; then
            # Branch never diverged - no work done yet
            echo -e "${BLUE}[clean]${NC}"
        else
            # Branch had commits that are now in target
            echo -e "${GREEN}[merged]${NC}"
        fi
    else
        echo -e "${YELLOW}[open]${NC}"
    fi
}

# ============================================
# List commands
# ============================================

# Command: list (porcelain output)
# Internal function for JSON output (uses jq for proper escaping)
cmd_list_porcelain() {
    local show_dirty_only="${1:-false}"
    local worktrees_json="[]"

    if [ -d "$WORKTREES_DIR" ] && [ "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
        for dir in "$WORKTREES_DIR"/*/; do
            [ -d "$dir" ] || continue

            local name=$(basename "$dir")
            local port=$(get_metadata "$name" "port")
            local branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
            local commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")

            # Check for uncommitted changes
            local is_dirty=false
            local staged=$(git -C "$dir" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
            local unstaged=$(git -C "$dir" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
            local untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
            if [ "$staged" -gt 0 ] || [ "$unstaged" -gt 0 ] || [ "$untracked" -gt 0 ]; then
                is_dirty=true
            fi

            # Skip if --dirty and not dirty
            if [ "$show_dirty_only" = true ] && [ "$is_dirty" = false ]; then
                continue
            fi

            local meta_base=$(get_metadata "$name" "base")
            local meta_desc=$(get_metadata "$name" "description")

            # Build worktree JSON object with proper escaping via jq
            local wt_json
            wt_json=$(jq -n \
                --arg name "$name" \
                --arg path "$dir" \
                --arg branch "$branch" \
                --arg commit "$commit" \
                --arg port "${port:-}" \
                --argjson dirty "$is_dirty" \
                --arg base "${meta_base:-}" \
                --arg description "${meta_desc:-}" \
                '{name: $name, path: $path, branch: $branch, commit: $commit, port: $port, dirty: $dirty, base: $base, description: $description}')

            # Append to array
            worktrees_json=$(echo "$worktrees_json" | jq --argjson wt "$wt_json" '. + [$wt]')
        done
    fi

    # Output final JSON with proper escaping
    jq -n \
        --arg project "$CURRENT_PROJECT" \
        --arg main_app "$MAIN_APP" \
        --arg worktrees_dir "$WORKTREES_DIR" \
        --argjson worktrees "$worktrees_json" \
        '{project: $project, main_app: $main_app, worktrees_dir: $worktrees_dir, worktrees: $worktrees}'
}

# Command: list
# Usage: pwt list [--dirty] [--porcelain] [--names]
cmd_list() {
    local show_dirty_only=false
    local porcelain=false
    local verbose=false
    local statusline=false
    local names_only=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                echo "Usage: pwt list [options]"
                echo ""
                echo "List all worktrees for the current project."
                echo ""
                echo "Options:"
                echo "  -d, --dirty      Only show dirty worktrees"
                echo "  -v, --verbose    Show detailed info (original format)"
                echo "  -q, --quick      Skip network operations (faster)"
                echo "  -r, --refresh    Force refresh cache"
                echo "  --porcelain      Output JSON (for scripts)"
                echo "  --names          Output only worktree names (for completions)"
                echo "  statusline       Compact single-line for prompts"
                echo ""
                echo "Examples:"
                echo "  pwt list              # Default tabular view"
                echo "  pwt list -d           # Only dirty worktrees"
                echo "  pwt list --porcelain  # JSON output"
                echo "  pwt list --names      # Just names (for shell completion)"
                return 0
                ;;
            -d|--dirty)
                show_dirty_only=true
                shift
                ;;
            --porcelain)
                porcelain=true
                shift
                ;;
            --verbose|-v)
                verbose=true
                shift
                ;;
            -q|--quick)
                LIST_QUICK_MODE=true
                shift
                ;;
            -r|--refresh)
                LIST_REFRESH_MODE=true
                shift
                ;;
            --names)
                names_only=true
                shift
                ;;
            statusline)
                statusline=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Names-only mode: output worktree names for shell completions
    if [ "$names_only" = true ]; then
        cmd_list_names
        return
    fi

    # Statusline mode: compact single-line for prompts
    if [ "$statusline" = true ]; then
        cmd_list_statusline
        return
    fi

    # Porcelain mode: output JSON
    if [ "$porcelain" = true ]; then
        cmd_list_porcelain "$show_dirty_only"
        return
    fi

    # Verbose mode: detailed output (original format)
    if [ "$verbose" = true ]; then
        cmd_list_verbose "$show_dirty_only"
        return
    fi

    # Default: compact tabular format with caching
    # Cache logic: first run slow (builds cache), subsequent runs fast (uses cache)
    # Cache always stores FULL list (no -d filter); -d filter applied on read

    local cache_file
    cache_file=$(get_list_cache_file)

    # Helper to read cache (with optional dirty filter)
    read_cache() {
        if [ "$show_dirty_only" = true ]; then
            read_list_cache_filtered
        else
            cat "$cache_file"
        fi
    }

    # Helper to generate cache (always full list, no -d filter)
    generate_cache() {
        init_cache_dir
        cmd_list_compact "" > "$cache_file"
    }

    # --refresh: clear cache and regenerate
    if [ "$LIST_REFRESH_MODE" = true ]; then
        clear_list_cache
        generate_cache
        read_cache
        return
    fi

    # --quick: always use cache if exists (even if stale)
    if [ "$LIST_QUICK_MODE" = true ]; then
        if [ -f "$cache_file" ]; then
            read_cache
            return
        fi
        # No cache, generate (but still skip network via LIST_QUICK_MODE)
        generate_cache
        read_cache
        return
    fi

    # Default: use cache if valid, else regenerate
    if is_list_cache_valid; then
        read_cache
    else
        generate_cache
        read_cache
    fi
}

# Print a table row with fixed column widths
# Usage: print_table_row <marker> <name> <branch> <hash> <base> <stat> <main_div> <remote_div> <age> <meta>
print_table_row() {
    local marker="$1"
    local name="$2"
    local branch="$3"
    local hash="$4"
    local base="$5"
    local stat="$6"
    local main_div="$7"
    local remote_div="$8"
    local age="$9"
    local meta="${10}"

    # Build row with proper visual padding for Unicode columns
    # Format: marker(2) name(20) branch(40) hash(8) base(8) stat(4) main(10) remote(10) age(4) meta
    printf "  %-2s " "$marker"
    pad_visual "${name:0:20}" 20
    printf " "
    pad_visual "${branch:0:40}" 40
    printf " "
    printf "%-8s " "${hash:0:8}"
    pad_visual "${base:0:8}" 8
    printf " "
    printf "%-4s " "${stat:-·}"
    pad_visual "${main_div:-·}" 10
    printf " "
    pad_visual "${remote_div:-·}" 10
    printf " "
    printf "%-4s " "$age"
    printf "%s\n" "$meta"
}

# Compact tabular list format (default)
cmd_list_compact() {
    local show_dirty_only="${1:-false}"

    # If project not cloned, show helpful message and exit
    if [ ! -d "$MAIN_APP" ]; then
        echo -e "${BLUE}${CURRENT_PROJECT}${NC}: ${YELLOW}not cloned${NC}"
        [ -n "$PROJECT_REMOTE" ] && echo -e "  Run: ${GREEN}pwt clone${NC}"
        return 0
    fi

    echo -e "${BLUE}${CURRENT_PROJECT}${NC}"
    echo ""

    # Print header
    print_table_row "" "Worktree" "Branch" "Hash" "Base" "Stat" "main↕" "Remote" "Age" "Meta"
    print_table_row "--" "--------------------" "----------------------------------------" "--------" "--------" "----" "----------" "----------" "----" "--------------------"

    # Main app row
    local main_branch=$(git -C "$MAIN_APP" branch --show-current 2>/dev/null || echo "?")
    local main_hash=$(get_short_hash "$MAIN_APP")
    local main_status=$(get_status_symbols "$MAIN_APP")
    local main_age_ts=$(git -C "$MAIN_APP" log -1 --format=%ct 2>/dev/null || echo "0")
    local main_age=$(format_relative_time "$main_age_ts")
    local main_remote=$(get_remote_divergence "$MAIN_APP")

    # Check if main is current
    local main_marker=" "
    if [ "$PWD" = "$MAIN_APP" ]; then
        main_marker="@"
    elif is_previous_worktree "$MAIN_APP"; then
        main_marker="*"
    fi

    print_table_row "$main_marker" "@" "$main_branch" "$main_hash" "·" "${main_status:-·}" "·" "${main_remote:-·}" "$main_age" "description=main application"

    # Prefetch remote refs once (performance: avoids N fetches in loop)
    prefetch_remote_refs

    # Worktrees
    local has_merged=false
    if [ -d "$WORKTREES_DIR" ] && [ "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
        for dir in "$WORKTREES_DIR"/*/; do
            [ -d "$dir" ] || continue
            local name=$(basename "$dir")

            # Git info
            local branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
            local hash=$(get_short_hash "$dir")
            local base=$(get_base_branch "$name" "$dir")

            # Status symbols
            local status=$(get_status_symbols "$dir")
            local is_dirty=false
            [ -n "$status" ] && is_dirty=true

            # Skip if --dirty and not dirty
            if [ "$show_dirty_only" = true ] && [ "$is_dirty" = false ]; then
                continue
            fi

            # Divergence from main
            local main_div=$(get_divergence "$dir" "origin/${DEFAULT_BRANCH:-master}")

            # Remote divergence
            local remote_div=$(get_remote_divergence "$dir")

            # Age
            local age_ts=$(git -C "$dir" log -1 --format=%ct 2>/dev/null || echo "0")
            local age=$(format_relative_time "$age_ts")

            # Markers: @ = current, * = previous
            local marker=" "
            if [ "$PWD" = "${dir%/}" ]; then
                marker="@"
            elif is_previous_worktree "${dir%/}"; then
                marker="*"
            fi

            # Check merge status for tips
            local merge_status=$(check_merge_status "$dir" "${DEFAULT_BRANCH:-master}" 2>/dev/null)
            if [[ "$merge_status" == *"merged"* ]] || [[ "$merge_status" == *"clean"* ]]; then
                has_merged=true
            fi

            # Build meta string from metadata (includes port, description, custom fields)
            local meta=$(get_extra_metadata "$name")

            # If no description in metadata, generate fallback
            if [[ "$meta" != *"description="* ]]; then
                local desc=""
                # Extract from branch name
                if [[ "$branch" =~ ^[^/]+/[A-Z]+-[0-9]+-(.*) ]]; then
                    desc=$(echo "${BASH_REMATCH[1]}" | tr '-' ' ')
                elif [[ ! "$branch" =~ ^[^/]+/[A-Z]+-[0-9]+$ ]]; then
                    if [[ "$branch" =~ ^[^/]+/(.+) ]]; then
                        desc=$(echo "${BASH_REMATCH[1]}" | tr '-' ' ')
                    fi
                fi
                # Fallback to commit message
                if [ -z "$desc" ]; then
                    desc=$(git -C "$dir" log --oneline --no-merges -1 --format=%s 2>/dev/null | head -c 40)
                fi
                [ -n "$desc" ] && meta="$meta description=$desc"
            fi

            [ -z "$meta" ] && meta="·"

            print_table_row "$marker" "$name" "$branch" "$hash" "$base" "${status:-·}" "${main_div:-·}" "${remote_div:-·}" "$age" "$meta"
        done
    fi

    echo ""

    # Tips
    if [ "$has_merged" = true ]; then
        echo -e "${YELLOW}Tip:${NC} Run ${GREEN}pwt auto-remove${NC} to clean up merged worktrees"
    fi

    # Legend
    echo -e "${BLUE}Legend:${NC} @ current  * previous  + staged  ! modified  ? untracked"
}

# Names-only output for shell completions
# Usage: pwt list --names
# Output: one worktree name per line with trailing / (directory style)
cmd_list_names() {
    # Always output @ for main app (with / to look like directory)
    echo "@/"

    # Output worktree names with trailing /
    if [ -d "$WORKTREES_DIR" ] && [ "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
        for dir in "$WORKTREES_DIR"/*/; do
            [ -d "$dir" ] || continue
            local name=$(basename "$dir")
            echo "$name/"
        done
    fi
}

# Statusline for shell prompts
# Usage: pwt list statusline
# Output: [TICKET-123 +! ↑3 ⇡2] or empty if in main
cmd_list_statusline() {
    # Only show if in a worktree
    local worktree=""
    local dir=""

    if [ -n "${PWT_WORKTREE:-}" ]; then
        worktree="$PWT_WORKTREE"
        dir="$WORKTREES_DIR/$worktree"
    else
        # Try to detect from PWD
        if [[ "$PWD" == *"-worktrees/"* ]]; then
            worktree=$(basename "$PWD")
            dir="$PWD"
        else
            # In main app or not in worktree - output nothing
            return 0
        fi
    fi

    [ ! -d "$dir" ] && return 0

    local status=$(get_status_symbols "$dir")
    local main_div=$(get_divergence "$dir" "origin/${DEFAULT_BRANCH:-master}")
    local remote_div=$(get_remote_divergence "$dir")

    # Build statusline
    local parts=()
    parts+=("$worktree")
    [ -n "$status" ] && parts+=("$status")
    [ -n "$main_div" ] && parts+=("$main_div")
    [ -n "$remote_div" ] && parts+=("$remote_div")

    echo "[${parts[*]}]"
}

# Verbose list format (original detailed format)
cmd_list_verbose() {
    local show_dirty_only="${1:-false}"

    echo -e "${BLUE}Worktrees (${CURRENT_PROJECT}):${NC}\n"

    # Show config info
    echo -e "  ${BLUE}Config:${NC}"

    # Project path
    if [ -d "$MAIN_APP" ]; then
        echo -e "    Path:      $MAIN_APP"
    else
        echo -e "    Path:      ${YELLOW}$MAIN_APP (not cloned)${NC}"
        [ -n "$PROJECT_REMOTE" ] && echo -e "    Remote:    $PROJECT_REMOTE"
    fi

    # Worktrees directory
    echo -e "    Worktrees: $WORKTREES_DIR"

    # Pwtfiles (show all that would be used)
    local pwtfiles=()
    local config_pwtfile=$(get_project_config "$CURRENT_PROJECT" "pwtfile")
    if [ -n "$config_pwtfile" ]; then
        config_pwtfile="${config_pwtfile/#\~/$HOME}"
        [[ "$config_pwtfile" != /* ]] && config_pwtfile="$MAIN_APP/$config_pwtfile"
        if [ -f "$config_pwtfile" ]; then
            pwtfiles+=("$config_pwtfile (config)")
        else
            pwtfiles+=("${config_pwtfile} ${YELLOW}(config, missing)${NC}")
        fi
    fi
    if [ -f "$MAIN_APP/Pwtfile" ]; then
        pwtfiles+=("$MAIN_APP/Pwtfile (local)")
    fi
    if [ -f "$PWT_DIR/Pwtfile" ]; then
        pwtfiles+=("$PWT_DIR/Pwtfile (global)")
    fi

    if [ ${#pwtfiles[@]} -gt 0 ]; then
        echo -e "    Pwtfile:   ${pwtfiles[0]}"
        for ((i=1; i<${#pwtfiles[@]}; i++)); do
            echo -e "               ${pwtfiles[$i]}"
        done
    else
        echo -e "    Pwtfile:   ${YELLOW}(none)${NC}"
    fi
    echo ""

    # If project not cloned, show helpful message and exit
    if [ ! -d "$MAIN_APP" ]; then
        echo -e "  ${YELLOW}Project not cloned.${NC}"
        if [ -n "$PROJECT_REMOTE" ]; then
            echo -e "  Run: ${GREEN}pwt clone${NC} to clone from remote"
        fi
        echo ""
        return 0
    fi

    # Main app - also used as default target for merge status
    local main_branch=$(git -C "$MAIN_APP" branch --show-current 2>/dev/null || echo "?")
    local default_target="${main_branch:-master}"
    local main_commit=$(git -C "$MAIN_APP" rev-parse --short HEAD 2>/dev/null || echo "?")
    echo -e "  ${YELLOW}${CURRENT_PROJECT}${NC} (main)"
    echo -e "    Branch: $main_branch @ $main_commit"
    echo -n "    Server: "
    check_server_status "$MAIN_APP"
    echo -n "    Port:   "
    check_port_status 5000 "$MAIN_APP"
    echo ""

    # Worktrees
    local has_port_issues=false
    local has_merged=false
    if [ -d "$WORKTREES_DIR" ] && [ "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
        for dir in "$WORKTREES_DIR"/*/; do
            if [ -d "$dir" ]; then
                local name=$(basename "$dir")

                # Get port from metadata first, fallback to extracting from name
                local port=$(get_metadata "$name" "port")
                if [ -z "$port" ]; then
                    # Legacy: extract from directory name if ends with -XXXX
                    if [[ "$name" =~ -([0-9]{4})$ ]]; then
                        port="${BASH_REMATCH[1]}"
                    fi
                fi

                # Git info
                local branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
                local commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "?")
                local upstream=$(git -C "$dir" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null || echo "")

                # Get metadata (if exists)
                local meta_base=$(get_metadata "$name" "base")
                local meta_base_commit=$(get_metadata "$name" "base_commit")
                local meta_desc=$(get_metadata "$name" "description")

                # Find base branch info
                local base_name=""
                local base_short=""
                local base_ahead=""

                if [ -n "$meta_base" ]; then
                    # Use metadata for base
                    base_name="$meta_base"
                    base_short="$meta_base_commit"
                    # Calculate ahead/behind from current base
                    local base_ref="origin/${meta_base#origin/}"
                    local base_commit=$(git -C "$dir" merge-base HEAD "$base_ref" 2>/dev/null)
                    if [ -n "$base_commit" ]; then
                        local commits_ahead=$(git -C "$dir" rev-list --count "${base_commit}..HEAD" 2>/dev/null || echo "0")
                        local commits_behind=$(git -C "$dir" rev-list --count "HEAD..$base_ref" 2>/dev/null || echo "0")
                        if [ "$commits_ahead" -gt 0 ] || [ "$commits_behind" -gt 0 ]; then
                            base_ahead=" (↑${commits_ahead} ↓${commits_behind})"
                        fi
                    fi
                else
                    # Fallback: calculate merge-base with default branch
                    base_name="${DEFAULT_BRANCH:-master}"
                    local base_commit=$(git -C "$dir" merge-base HEAD "origin/${DEFAULT_BRANCH:-master}" 2>/dev/null)
                    if [ -n "$base_commit" ]; then
                        base_short=$(git -C "$dir" rev-parse --short "$base_commit" 2>/dev/null)
                        local commits_ahead=$(git -C "$dir" rev-list --count "${base_commit}..HEAD" 2>/dev/null || echo "0")
                        local commits_behind=$(git -C "$dir" rev-list --count "HEAD..origin/${DEFAULT_BRANCH:-master}" 2>/dev/null || echo "0")
                        if [ "$commits_ahead" -gt 0 ] || [ "$commits_behind" -gt 0 ]; then
                            base_ahead=" (↑${commits_ahead} ↓${commits_behind})"
                        fi
                    fi
                fi

                # Get description from metadata or extract from branch name
                local desc=""
                if [ -n "$meta_desc" ]; then
                    desc="$meta_desc"
                elif [ -n "$branch" ] && [ "$branch" != "detached" ]; then
                    desc=$(echo "$branch" | sed -E 's|^[a-z]+/||')
                    desc=$(echo "$desc" | tr '-' ' ')
                fi

                # Check for uncommitted changes
                local changes=""
                local is_dirty=false
                local staged=$(git -C "$dir" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
                local unstaged=$(git -C "$dir" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
                local untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
                if [ "$staged" -gt 0 ] || [ "$unstaged" -gt 0 ] || [ "$untracked" -gt 0 ]; then
                    is_dirty=true
                    local parts=()
                    [ "$staged" -gt 0 ] && parts+=("${staged} staged")
                    [ "$unstaged" -gt 0 ] && parts+=("${unstaged} modified")
                    [ "$untracked" -gt 0 ] && parts+=("${untracked} untracked")
                    changes=$(IFS=', '; echo "${parts[*]}")
                fi

                # Skip if --dirty and not dirty
                if [ "$show_dirty_only" = true ] && [ "$is_dirty" = false ]; then
                    continue
                fi

                # Title with description
                if [ -n "$desc" ]; then
                    echo -e "  ${YELLOW}$name${NC} - ${desc}"
                else
                    echo -e "  ${YELLOW}$name${NC}"
                fi

                # Branch and commit
                echo -e "    Branch: $branch @ $commit"

                # Base (where it was created from)
                if [ -n "$base_short" ]; then
                    echo -e "    Base:   $base_name @ $base_short$base_ahead"
                fi

                # Upstream/target only if different from "origin/<branch>" (i.e., meaningful)
                if [ -n "$upstream" ] && [ "$upstream" != "origin/$branch" ] && [ "$upstream" != "origin/${DEFAULT_BRANCH:-master}" ]; then
                    echo -e "    Target: $upstream"
                fi

                # Uncommitted changes
                if [ -n "$changes" ]; then
                    echo -e "    Changes: ${YELLOW}$changes${NC}"
                fi

                # Server status
                echo -n "    Server: "
                check_server_status "$dir"

                # Port status
                echo -n "    Port:   "
                local port_status=$(check_port_status "$port" "$dir")
                echo -e "$port_status"
                if [[ "$port_status" == *"conflict"* ]]; then
                    has_port_issues=true
                fi

                # Merge status
                echo -n "    Status: "
                local merge_status=$(check_merge_status "$dir" "$default_target")
                echo -e "$merge_status"
                if [[ "$merge_status" == *"merged"* ]] || [[ "$merge_status" == *"clean"* ]]; then
                    has_merged=true
                fi
                echo ""
            fi
        done
    else
        echo -e "  ${YELLOW}(no worktrees created)${NC}"
        echo ""
    fi

    # Tips
    if [ "$has_port_issues" = true ]; then
        echo -e "${YELLOW}Tip:${NC} Use ${GREEN}pwt fix-port <worktree>${NC} to resolve occupied ports"
    fi
    if [ "$has_merged" = true ]; then
        echo -e "${YELLOW}Tip:${NC} Use ${GREEN}pwt auto-remove${NC} to clean up merged worktrees"
    fi
    if [ "$has_port_issues" = false ] && [ "$has_merged" = false ]; then
        echo ""
    fi
}

# Command: tree
# Visual tree view of worktrees - mental map of active work
# Usage: pwt tree [--all] [--dirty] [--ports] [--short]
cmd_tree() {
    local show_all=false
    local show_dirty_only=false
    local show_ports=false
    local short_mode=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --all|-a)
                show_all=true
                shift
                ;;
            --dirty|-d)
                show_dirty_only=true
                shift
                ;;
            --ports|-p)
                show_ports=true
                shift
                ;;
            --short|-s)
                short_mode=true
                shift
                ;;
            -h|--help)
                echo "Usage: pwt tree [--all] [--dirty] [--ports] [--short]"
                echo ""
                echo "Visual tree view of worktrees - mental map of active work."
                echo ""
                echo "Options:"
                echo "  --all, -a     Show all projects (global view)"
                echo "  --dirty, -d   Show only dirty worktrees"
                echo "  --ports, -p   Show port mappings"
                echo "  --short, -s   One line per worktree"
                echo ""
                echo "Examples:"
                echo "  pwt tree              # current project"
                echo "  pwt tree --all        # all projects"
                echo "  pwt tree --dirty      # only dirty worktrees"
                echo "  pwt tree --ports      # show ports"
                return 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                return 1
                ;;
        esac
    done

    # Helper to render a project tree
    _render_project_tree() {
        local project="$1"
        local project_dir="$PROJECTS_DIR/$project"
        local config_file="$project_dir/config.json"
        local main_app=""
        local worktrees_dir=""

        # Try to get paths from config file first, fall back to global vars
        if [ -f "$config_file" ]; then
            main_app=$(jq -r '.path // empty' "$config_file")
            worktrees_dir=$(jq -r '.worktrees_dir // empty' "$config_file")
        fi

        # Fall back to global variables (for auto-detected projects)
        [ -z "$main_app" ] && main_app="$MAIN_APP"
        [ -z "$worktrees_dir" ] && worktrees_dir="$WORKTREES_DIR"

        [ -d "$main_app" ] || return

        # Project header
        echo -e "${YELLOW}${project}/${NC}"

        # Main app
        local main_branch=$(git -C "$main_app" branch --show-current 2>/dev/null || echo "?")
        local main_status=""
        if [ -n "$(git -C "$main_app" status --porcelain 2>/dev/null)" ]; then
            main_status=" ${RED}*${NC}"
        fi
        if [ "$short_mode" = true ]; then
            echo -e "├─ ${GREEN}@${NC} main ($main_branch)$main_status"
        else
            echo -e "├─ ${GREEN}@${NC} (main)"
            echo -e "│  └─ $main_branch$main_status"
        fi

        # Worktrees
        if [ -d "$worktrees_dir" ] && [ "$(ls -A "$worktrees_dir" 2>/dev/null)" ]; then
            local wt_dirs=("$worktrees_dir"/*/)
            local wt_count=${#wt_dirs[@]}
            local i=0

            for dir in "${wt_dirs[@]}"; do
                [ -d "$dir" ] || continue
                i=$((i + 1))

                local name=$(basename "$dir")
                local branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
                local desc=$(get_metadata "$name" "description" 2>/dev/null)
                local port=$(get_metadata "$name" "port" 2>/dev/null)

                # Status
                local status_text=""
                local is_dirty=false
                if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
                    local dirty_count=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
                    status_text=" ${RED}*${dirty_count}${NC}"
                    is_dirty=true
                fi

                # Skip if --dirty and not dirty
                if [ "$show_dirty_only" = true ] && [ "$is_dirty" = false ]; then
                    continue
                fi

                # Current marker
                local current_marker=""
                local current_name=$(get_current_from_symlink 2>/dev/null)
                if [ "$name" = "$current_name" ]; then
                    current_marker=" ${BLUE}[current]${NC}"
                fi

                # Tree connector
                local connector="├─"
                if [ $i -eq $wt_count ]; then
                    connector="└─"
                fi

                # Port info
                local port_text=""
                if [ "$show_ports" = true ] && [ -n "$port" ]; then
                    port_text=" :$port"
                fi

                if [ "$short_mode" = true ]; then
                    echo -e "$connector $branch$port_text$status_text$current_marker"
                else
                    echo -e "$connector ${GREEN}$name${NC}$current_marker"
                    [ -n "$desc" ] && echo -e "│  ├─ \"$desc\""
                    echo -e "│  ├─ $branch$port_text"
                    echo -e "│  └─ status:$status_text${status_text:- ${GREEN}clean${NC}}"
                fi
            done
        else
            echo -e "└─ ${DIM}(no worktrees)${NC}"
        fi

        echo ""
    }

    init_metadata

    if [ "$show_all" = true ]; then
        # Global view - all projects
        echo -e "${DIM}~/.pwt/projects/${NC}"
        echo ""
        for project_dir in "$PROJECTS_DIR"/*/; do
            [ -d "$project_dir" ] || continue
            local project=$(basename "$project_dir")
            _render_project_tree "$project"
        done
    else
        # Current project only
        require_project
        _render_project_tree "$CURRENT_PROJECT"
    fi
}
