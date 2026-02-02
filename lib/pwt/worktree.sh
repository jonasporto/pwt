#!/bin/bash
# ============================================================
# pwt worktree module
# Worktree creation, removal, and maintenance operations
# ============================================================
#
# This module is sourced by bin/pwt for worktree management commands.
#
# Dependencies:
#   - Requires functions from bin/pwt: init_metadata, get_metadata, set_metadata,
#     remove_metadata, next_available_port, clear_list_cache, run_pwtfile,
#     has_pwtfile, detect_default_branch, prefetch_remote_refs
#   - Requires variables: MAIN_APP, WORKTREES_DIR, BRANCH_PREFIX, CURRENT_PROJECT,
#     PWT_DIR, RED, GREEN, BLUE, YELLOW, CYAN, DIM, NC
#

# Guard against multiple sourcing
[[ -n "${_PWT_WORKTREE_LOADED:-}" ]] && return 0
_PWT_WORKTREE_LOADED=1

cmd_create() {
    local branch=""
    local base_ref=""
    local description=""
    local dry_run=false
    local open_editor=false
    local start_ai=false
    local from_current=false
    local use_clone=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n)
                dry_run=true
                shift
                ;;
            -e|--editor)
                open_editor=true
                shift
                ;;
            -a|--ai)
                start_ai=true
                shift
                ;;
            --clone)
                use_clone=true
                shift
                ;;
            --from)
                base_ref="$2"
                shift 2
                ;;
            --from-current)
                from_current=true
                shift
                ;;
            --)
                # Everything after -- is the description
                shift
                description="$*"
                break
                ;;
            -h|--help)
                echo "Usage: pwt create <branch> [base] [-- description]"
                echo ""
                echo "Arguments:"
                echo "  branch          Branch name or ticket (e.g., TICKET-1234)"
                echo "  base            Base branch (default: master)"
                echo "  -- description  Optional description after --"
                echo ""
                echo "Options:"
                echo "  --from <ref>      Create from specific ref (tag, commit, branch)"
                echo "  --from-current    Create from current branch"
                echo "  --clone           Use git clone instead of worktree"
                echo "  -e, --editor      Open in editor after creation"
                echo "  -a, --ai          Start AI assistant after creation"
                echo "  -n, --dry-run     Show what would be done"
                echo "  -h, --help        Show this help"
                return 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
            *)
                # Positional arguments: branch, base_ref, description
                if [ -z "$branch" ]; then
                    branch="$1"
                elif [ -z "$base_ref" ]; then
                    base_ref="$1"
                else
                    # Accumulate all remaining positional args as description
                    if [ -z "$description" ]; then
                        description="$1"
                    else
                        description="$description $1"
                    fi
                fi
                shift
                ;;
        esac
    done

    # Handle --from-current: use current branch as base
    if [ "$from_current" = true ]; then
        cd "$MAIN_APP"
        base_ref=$(git branch --show-current 2>/dev/null)
        if [ -z "$base_ref" ]; then
            pwt_error "Error: Could not detect current branch"
            exit 1
        fi
    fi

    if [ -z "$branch" ]; then
        pwt_error "Error: Branch/ticket not specified"
        echo "Usage: pwt create <branch> [base-ref] [description...] [options]"
        echo "       pwt create <branch> [options] -- description with spaces"
        echo ""
        echo "Options:"
        echo "  --dry-run, -n     Show what would be created without creating"
        echo "  -e, --editor      Open editor after creating"
        echo "  -a, --ai          Start AI tool after creating"
        echo "  --from <ref>      Create from specific ref (tag, commit, branch)"
        echo "  --from-current    Create from current branch"
        echo "  --                Everything after is the description"
        echo ""
        echo "Examples:"
        echo "  pwt create feature/my-feature"
        echo "  pwt create PROJ-123 master"
        echo "  pwt create PROJ-123 master \"add auth flow\""
        echo "  pwt create PROJ-123 master add auth flow        # works too"
        echo "  pwt create PROJ-123 --from v1.2.3 -- hotfix for bug"
        echo "  pwt create hotfix --from-current"
        echo "  pwt create PROJ-123 master -e -a"
        exit 1
    fi

    # Ensure worktrees_dir exists
    mkdir -p "$WORKTREES_DIR"

    pwt_debug "Creating worktree: branch=$branch, base=${base_ref:-default}, from_current=${from_current:-false}"
    pwt_debug "Options: dry_run=${dry_run:-false}, open_editor=${open_editor:-false}, start_ai=${start_ai:-false}"

    # Extract worktree name from branch (removes path prefix, sanitizes)
    local worktree_name=$(extract_worktree_name "$branch")
    local worktree_dir="$WORKTREES_DIR/$worktree_name"

    # Check if worktree already exists
    if [ -d "$worktree_dir" ]; then
        pwt_error "Error: Worktree already exists: $worktree_name"
        echo ""
        echo "Options:"
        echo "  1. Remove existing: pwt remove $worktree_name"
        echo "  2. Use a different branch name"
        exit $EXIT_CONFLICT
    fi

    # Read PORT_BASE from Pwtfile (if defined)
    read_port_base

    # Acquire lock to prevent port allocation race condition
    # Lock is held until metadata is saved
    if ! acquire_metadata_lock; then
        pwt_error "Error: Could not acquire lock for port allocation"
        exit 1
    fi
    # Ensure lock is released on exit
    trap 'release_metadata_lock' EXIT

    # Allocate port (stored in metadata only)
    local port=$(next_available_port)

    cd "$MAIN_APP"

    # Determine if need to create new branch or use existing
    local new_branch_name=""
    local git_worktree_args=()

    if [ -n "$base_ref" ]; then
        # Base ref provided: create new branch from it
        # Format: [prefix]ticket-name or [prefix]ticket-name-description-slug
        if [ -n "$description" ]; then
            # Convert description to slug: lowercase, spaces -> hyphens, remove special chars
            local slug=$(echo "$description" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
            new_branch_name="${BRANCH_PREFIX}${worktree_name}-${slug}"
        else
            new_branch_name="${BRANCH_PREFIX}${worktree_name}"
        fi

        # Fetch base ref if remote
        if [[ "$base_ref" == origin/* ]] || [[ "$base_ref" == "master" ]] || [[ "$base_ref" == "main" ]]; then
            local remote_ref="origin/${base_ref#origin/}"
            echo -e "${BLUE}Updating reference:${NC} $remote_ref"
            git fetch origin "${base_ref#origin/}" --quiet 2>/dev/null || true
            base_ref="$remote_ref"
        fi

        local mode_label="worktree"
        [ "$use_clone" = true ] && mode_label="clone"

        echo -e "${BLUE}Creating $mode_label:${NC} $worktree_name"
        echo -e "  New branch: $new_branch_name"
        echo -e "  Base:   $base_ref"
        echo -e "  Port:   $port"
        echo -e "  Dir:    $worktree_dir"
        echo ""

        git_worktree_args=(-b "$new_branch_name" "$worktree_dir" "$base_ref")
    else
        # No base ref: use existing branch
        local mode_label="worktree"
        [ "$use_clone" = true ] && mode_label="clone"

        echo -e "${BLUE}Creating $mode_label:${NC} $worktree_name"
        echo -e "  Branch: $branch"
        echo -e "  Port:   $port"
        echo -e "  Dir:    $worktree_dir"
        echo ""

        # --guess-remote: auto-detect remote tracking branch (e.g., origin/branch)
        git_worktree_args=("--guess-remote" "$worktree_dir" "$branch")
    fi

    # Dry-run mode: show what would be created without creating
    if [ "$dry_run" = true ]; then
        local mode_str="worktree"
        [ "$use_clone" = true ] && mode_str="clone"
        echo -e "${YELLOW}[DRY-RUN] Would create $mode_str with above settings${NC}"
        echo ""
        echo "Run without --dry-run to create."
        exit 0
    fi

    # Check for submodules (warn but don't block) - only for worktree mode
    if [ "$use_clone" = false ]; then
        if ! detect_submodules "$MAIN_APP"; then
            release_metadata_lock
            exit 1
        fi
    fi

    # Create workspace (worktree or clone)
    local workspace_mode="worktree"
    if [ "$use_clone" = true ]; then
        workspace_mode="clone"
        echo "Cloning repository..."
        git clone --quiet "$MAIN_APP" "$worktree_dir"

        # Checkout the correct branch
        cd "$worktree_dir"
        local final_branch="${new_branch_name:-$branch}"

        if [ -n "$new_branch_name" ]; then
            # Create new branch from base
            local checkout_base="${base_ref:-HEAD}"
            # If base is remote ref, fetch it first
            if [[ "$checkout_base" == origin/* ]]; then
                git fetch origin "${checkout_base#origin/}" --quiet 2>/dev/null || true
            fi
            git checkout -b "$new_branch_name" "$checkout_base" --quiet 2>/dev/null || \
                git checkout -b "$new_branch_name" "origin/${checkout_base#origin/}" --quiet 2>/dev/null || \
                git checkout -b "$new_branch_name" --quiet
        else
            # Checkout existing branch
            git checkout "$branch" --quiet 2>/dev/null || \
                git checkout -b "$branch" "origin/$branch" --quiet 2>/dev/null || true
        fi
        cd - > /dev/null
        echo -e "  ${GREEN}✓ Clone created${NC}"
    else
        # Create worktree (original logic)
        git worktree add "${git_worktree_args[@]}"
    fi

    # Save metadata
    local final_branch="${new_branch_name:-$branch}"
    local final_base="${base_ref:-master}"
    local final_base_commit=$(git -C "$worktree_dir" merge-base HEAD "origin/${final_base#origin/}" 2>/dev/null || git -C "$worktree_dir" rev-parse HEAD 2>/dev/null)
    local final_base_short=$(git -C "$worktree_dir" rev-parse --short "$final_base_commit" 2>/dev/null || echo "?")
    local final_desc="${description:-}"

    save_metadata "$worktree_name" "$worktree_dir" "$final_branch" "$final_base" "$final_base_short" "$port" "$final_desc" "$workspace_mode"
    echo -e "  ${GREEN}✓ Metadata saved${NC}"

    # Release port allocation lock now that metadata is saved
    release_metadata_lock
    trap - EXIT  # Clear the exit trap

    # Set context for Pwtfile and hooks
    export PWT_WORKTREE="$worktree_name"
    export PWT_WORKTREE_PATH="$worktree_dir"
    export PWT_BRANCH="$final_branch"
    export PWT_PORT="$port"
    export PWT_TICKET="$worktree_name"  # User can customize via Pwtfile
    export PWT_BASE="$final_base"
    export PWT_DESC="$final_desc"
    export PWT_PROJECT="$CURRENT_PROJECT"
    export MAIN_APP="$MAIN_APP"

    # Run Pwtfile setup (if exists), then hook
    run_pwtfile "setup"
    run_hook "post-create"

    # Auto-set as current worktree (non-fatal)
    set_current_worktree "$worktree_name" 2>/dev/null || true

    local mode_label="Worktree"
    [ "$workspace_mode" = "clone" ] && mode_label="Clone" || true

    echo -e "\n${GREEN}✓ $mode_label created successfully!${NC}"
    clear_list_cache  # Invalidate cache so next list shows new worktree
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo -e "  Navigate:    ${DIM}pwt cd ${worktree_name}${NC}  or  ${DIM}cd $worktree_dir${NC}"
    echo -e "  Open editor: ${DIM}pwt editor ${worktree_name}${NC}"
    echo -e "  Start AI:    ${DIM}pwt ai ${worktree_name}${NC}"
    echo -e "  Run server:  ${DIM}pwt server ${worktree_name}${NC}  (port ${port})"
    echo ""
    echo -e "  ${DIM}Tip: Set as current with 'pwt use ${worktree_name}' for quick access${NC}"

    # Open editor if requested
    if [ "$open_editor" = true ]; then
        echo ""
        cmd_editor "$worktree_name"
    fi

    # Start AI tool if requested
    if [ "$start_ai" = true ]; then
        echo ""
        cmd_ai "$worktree_name"
    fi

    return 0
}

# ============================================
# Worktree maintenance commands
# ============================================

cmd_repair() {
    local name="$1"

    # Normalize: strip trailing slash (from shell completion)
    name="${name%/}"

    if [ -n "$name" ]; then
        # Repair specific worktree
        local worktree_dir="$WORKTREES_DIR/$name"
        if [ ! -d "$worktree_dir" ]; then
            pwt_error "Error: Worktree not found: $name"
            exit $EXIT_NOT_FOUND
        fi
        echo -e "${BLUE}Repairing: $name${NC}"
        export PWT_WORKTREE="$name"
        export PWT_WORKTREE_PATH="$worktree_dir"
        cd "$worktree_dir"
        run_pwtfile "repair"
        run_hook "repair"
    else
        # Repair all worktrees
        echo -e "${BLUE}Repairing all worktrees...${NC}\n"

        if [ -d "$WORKTREES_DIR" ] && [ "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
            for dir in "$WORKTREES_DIR"/*/; do
                [ -d "$dir" ] || continue
                local wt_name=$(basename "$dir")
                echo -e "  ${YELLOW}$wt_name${NC}"
                export PWT_WORKTREE="$wt_name"
                export PWT_WORKTREE_PATH="$dir"
                cd "$dir"
                run_pwtfile "repair"
                run_hook "repair"
            done
        fi

        echo ""
        echo -e "${GREEN}Done!${NC}"
    fi
}

# Command: auto-remove (cleanup merged worktrees)
# Usage: pwt auto-remove [target] [--execute] [--dry-run]
# SAFETY: Dry-run by default. Must pass --execute to actually remove.
cmd_auto_remove() {
    local target_branch=""
    local dry_run=true  # SAFE DEFAULT: dry-run unless --execute
    local force_execute=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --execute|--yes|-y)
                force_execute=true
                dry_run=false
                shift
                ;;
            --dry-run|-n)
                dry_run=true
                shift
                ;;
            -h|--help)
                echo "Usage: pwt auto-remove [target] [options]"
                echo ""
                echo "Safely remove worktrees that have been merged into target branch."
                echo ""
                echo "Arguments:"
                echo "  target          Target branch to check merges against (default: current)"
                echo ""
                echo "Options:"
                echo "  --execute, -y   Actually remove (default is dry-run)"
                echo "  --dry-run, -n   Preview what would be removed (default)"
                echo "  -h, --help      Show this help"
                echo ""
                echo "Safety:"
                echo "  - Dry-run by default (shows what would be removed)"
                echo "  - Dirty worktrees backed up to ~/.pwt/trash/"
                echo "  - Requires --execute for non-interactive use"
                return 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
            *)
                target_branch="$1"
                shift
                ;;
        esac
    done

    # SAFETY: Require interactive terminal or --execute flag
    if [ "$force_execute" = false ] && [ ! -t 0 ]; then
        echo -e "${RED}⛔ SAFETY: auto-remove requires --execute flag when run non-interactively${NC}"
        echo "This prevents accidental data loss from automated scripts."
        echo ""
        echo "Usage: pwt auto-remove [target] --execute"
        exit 1
    fi

    # If no branch specified, use current branch from main app
    if [ -z "$target_branch" ]; then
        cd "$MAIN_APP"
        target_branch=$(git branch --show-current 2>/dev/null)
        if [ -z "$target_branch" ]; then
            pwt_error "Error: Could not detect current branch"
            echo "Usage: pwt auto-remove [target]"
            exit 1
        fi
        echo -e "${BLUE}Target branch (detected):${NC} $target_branch"
    fi

    echo -e "${BLUE}Checking worktrees merged into:${NC} $target_branch\n"

    # Fetch to ensure updated branches
    cd "$MAIN_APP"
    git fetch origin "$target_branch" --quiet 2>/dev/null || {
        pwt_error "Error: Branch '$target_branch' not found on remote"
        exit 1
    }

    # Use origin/$target_branch for comparison (freshly fetched)
    local remote_target="origin/$target_branch"

    # List worktrees to remove
    local to_remove=()
    local pending=()

    if [ ! -d "$WORKTREES_DIR" ] || [ -z "$(ls -A "$WORKTREES_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No worktrees found${NC}"
        exit 0
    fi

    for dir in "$WORKTREES_DIR"/*/; do
        [ -d "$dir" ] || continue

        local name=$(basename "$dir")

        # Get worktree HEAD commit
        local wt_commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null)

        # Skip worktrees without valid commit (corrupted)
        if [ -z "$wt_commit" ]; then
            echo -e "  ${YELLOW}⚠️  CORRUPTED:${NC} $name (no commit)"
            to_remove+=("$name")
            continue
        fi

        local wt_branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        local branch_display="${wt_branch:-detached}"

        # Check if worktree has uncommitted changes
        # SAFETY: Assume dirty if check fails (fail-safe)
        local is_dirty=true
        local git_status
        if git_status=$(git -C "$dir" status --porcelain 2>&1); then
            if [ -z "$git_status" ]; then
                is_dirty=false
            fi
        else
            echo -e "  ${RED}⚠️  CHECK FAILED:${NC} $name - cannot verify clean state, assuming dirty"
        fi

        # Check if worktree commit is contained in remote target branch (post-fetch)
        # Uses merge-base --is-ancestor which works even if remote branch was deleted
        if git merge-base --is-ancestor "$wt_commit" "$remote_target" 2>/dev/null; then
            if [ "$is_dirty" = true ]; then
                # Merged but has uncommitted changes - protect it
                echo -e "  ${YELLOW}⚠️  DIRTY:${NC} $name ($branch_display) - merged but has uncommitted changes"
                pending+=("$name")
            else
                echo -e "  ${GREEN}✅ MERGED:${NC} $name ($branch_display)"
                to_remove+=("$name")
            fi
        else
            echo -e "  ${YELLOW}⏳ PENDING:${NC} $name ($branch_display)"
            pending+=("$name")
        fi
    done

    echo ""

    # If nothing to remove, exit
    if [ ${#to_remove[@]} -eq 0 ]; then
        echo -e "${GREEN}No worktrees to remove${NC}"
        echo -e "Kept: ${#pending[@]}"
        exit 0
    fi

    # Dry-run mode: just show what would be removed
    if [ "$dry_run" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would remove ${#to_remove[@]} worktree(s):${NC}"
        for name in "${to_remove[@]}"; do
            echo "  - $name"
        done
        echo ""
        echo -e "Would keep: ${#pending[@]}"
        exit 0
    fi

    # Remove merged worktrees
    echo -e "${BLUE}Removing ${#to_remove[@]} worktree(s)...${NC}\n"

    local removed=0
    for name in "${to_remove[@]}"; do
        echo -e "${YELLOW}Removing: $name${NC}"
        if cmd_remove "$name" 2>&1; then
            removed=$((removed + 1))
        else
            # SAFETY: Only manually remove if directory is truly empty or has no git data
            local wt_dir="$WORKTREES_DIR/$name"
            if [ -d "$wt_dir" ]; then
                # Check if it has any files (besides .git)
                local file_count=$(find "$wt_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
                local dir_count=$(find "$wt_dir" -maxdepth 1 -type d ! -name ".git" ! -name "." 2>/dev/null | wc -l | tr -d ' ')

                if [ "$file_count" -gt 0 ] || [ "$dir_count" -gt 0 ]; then
                    echo -e "  ${RED}⛔ SAFETY: Cannot manually remove - directory has files${NC}"
                    echo -e "  Use 'pwt remove $name -y' to force removal"
                    continue
                fi

                # Empty or git-only directory - safe to remove
                rm -rf "$wt_dir" 2>/dev/null && {
                    echo -e "  ${GREEN}✓ Removed empty/corrupted worktree${NC}"
                    removed=$((removed + 1))
                }
            fi
        fi
        echo ""
    done

    echo -e "${GREEN}Done!${NC}"
    echo -e "  Removed: $removed"
    echo -e "  Kept:    ${#pending[@]}"
}

# Command: remove
cmd_remove() {
    local name=""
    local with_branch=false
    local force_branch=false
    local kill_port=false
    local kill_sidekiq=false
    local auto_yes=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --with-branch)
                with_branch=true
                shift
                ;;
            --force-branch)
                with_branch=true
                force_branch=true
                shift
                ;;
            --kill-port)
                kill_port=true
                shift
                ;;
            --kill-sidekiq)
                kill_sidekiq=true
                shift
                ;;
            --kill-all)
                kill_port=true
                kill_sidekiq=true
                shift
                ;;
            -y|--yes)
                auto_yes=true
                shift
                ;;
            -h|--help)
                echo "Usage: pwt remove [worktree] [options]"
                echo ""
                echo "Arguments:"
                echo "  worktree        Worktree name (default: current)"
                echo ""
                echo "Options:"
                echo "  --with-branch     Also delete the branch (if merged)"
                echo "  --force-branch    Force delete the branch (even if not merged)"
                echo "  --kill-port       Kill processes using the port"
                echo "  --kill-sidekiq    Kill Sidekiq processes"
                echo "  --kill-all        Kill both port and Sidekiq processes"
                echo "  -y, --yes         Skip confirmation prompts"
                echo "  -h, --help        Show this help"
                echo ""
                echo "Safety: Dirty worktrees are backed up to ~/.pwt/trash/"
                return 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done

    # If no name, try to use current worktree
    if [ -z "$name" ]; then
        if [ -n "${PWT_WORKTREE:-}" ]; then
            name="$PWT_WORKTREE"
        elif [[ "$PWD" == *"-worktrees/"* ]]; then
            name=$(basename "$PWD")
        else
            pwt_error "Error: Not in a worktree. Specify target."
            echo "Usage: pwt remove [worktree] [--with-branch] [--force-branch]"
            exit 1
        fi
        echo -e "${BLUE}Removing current worktree: $name${NC}"
    fi

    # Normalize name: strip trailing slash (from shell completion)
    name="${name%/}"

    # Protect main app from removal
    if [ "$name" = "@" ]; then
        pwt_error "Error: Cannot remove the main application."
        echo "Use 'git' commands directly if you need to modify the main repository."
        exit 1
    fi

    local worktree_dir="$WORKTREES_DIR/$name"

    if [ ! -d "$worktree_dir" ]; then
        pwt_error "Error: Worktree not found: $name"
        exit 1
    fi

    # Get port from metadata, fallback to extracting from name
    local port=$(get_metadata "$name" "port")
    if [ -z "$port" ]; then
        # Legacy: extract from directory name if ends with -XXXX
        if [[ "$name" =~ -([0-9]{4})$ ]]; then
            port="${BASH_REMATCH[1]}"
        fi
    fi

    # Detect processes on port (generic - no framework-specific checks)
    local port_pids=""
    local port_info=""
    if [ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] && has_lsof; then
        local pids_on_port=$(get_pids_on_port "$port")
        for pid in $pids_on_port; do
            local proc_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            local proc_cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
            port_pids="${port_pids}${port_pids:+ }$pid"
            port_info="${port_info}  PID $pid ($proc_name): $proc_cmd\n"
        done
    fi

    # Handle blocking processes
    if [ -n "$port_pids" ]; then
        if [ "$kill_port" = true ] || [ "$kill_sidekiq" = true ]; then
            echo -e "${YELLOW}Processes on port $port:${NC}"
            echo -e "$port_info"
            if [ "$auto_yes" = true ] || confirm_action "Kill these processes?"; then
                echo "$port_pids" | xargs kill -9 2>/dev/null || true
                sleep 1
                echo -e "  ${GREEN}✓ Port $port freed${NC}"
            else
                echo -e "${RED}Aborted.${NC}"
                exit 1
            fi
        else
            pwt_error "Error: Processes detected on port $port:"
            echo -e "$port_info"
            echo ""
            echo "Options:"
            echo "  pwt remove $name --kill-port    # Kill port processes"
            echo "  pwt remove $name --kill-port -y # Kill without confirmation"
            exit 1
        fi
    fi

    echo -e "${YELLOW}Removing worktree: $name${NC}"

    # SAFETY: Check for uncommitted changes before removing
    local has_changes=false
    local changes_detail=""

    if [ -d "$worktree_dir" ]; then
        # Check using BOTH methods for maximum safety
        local porcelain_status=$(git -C "$worktree_dir" status --porcelain 2>/dev/null)
        local untracked_count=$(git -C "$worktree_dir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        local staged_count=$(git -C "$worktree_dir" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
        local modified_count=$(git -C "$worktree_dir" diff --name-only 2>/dev/null | wc -l | tr -d ' ')

        if [ -n "$porcelain_status" ] || [ "$untracked_count" -gt 0 ] || [ "$staged_count" -gt 0 ] || [ "$modified_count" -gt 0 ]; then
            has_changes=true
            changes_detail="staged=$staged_count, modified=$modified_count, untracked=$untracked_count"
        fi
    fi

    if [ "$has_changes" = true ]; then
        echo -e "${RED}⚠️  WARNING: Worktree has uncommitted changes!${NC}"
        echo -e "    ${changes_detail}"
        echo ""
        git -C "$worktree_dir" status --short 2>/dev/null | head -10
        echo ""

        if [ "$auto_yes" = true ]; then
            echo -e "${YELLOW}Proceeding due to -y flag (changes will be LOST)${NC}"
        elif [ -t 0 ]; then
            # Interactive terminal - ask for confirmation
            if ! confirm_action "Are you SURE you want to remove this worktree? Changes will be PERMANENTLY LOST!"; then
                echo -e "${GREEN}Aborted. Worktree preserved.${NC}"
                exit 1
            fi
        else
            # Non-interactive - refuse to proceed
            echo -e "${RED}⛔ SAFETY: Cannot remove dirty worktree non-interactively${NC}"
            echo "Use 'pwt remove $name -y' to force removal"
            exit 1
        fi
    fi

    # Get metadata for hooks/Pwtfile
    local branch=$(get_metadata "$name" "branch")
    local base=$(get_metadata "$name" "base")
    local desc=$(get_metadata "$name" "description")
    # Set context for Pwtfile and hooks
    export PWT_WORKTREE="$name"
    export PWT_WORKTREE_PATH="$worktree_dir"
    export PWT_BRANCH="$branch"
    export PWT_PORT="$port"
    export PWT_TICKET="$name"  # User can customize via Pwtfile
    export PWT_BASE="$base"
    export PWT_DESC="$desc"
    export PWT_PROJECT="$CURRENT_PROJECT"
    export MAIN_APP="$MAIN_APP"

    # Run Pwtfile teardown (if exists), then hook
    # (Pwtfile handles project-specific cleanup like databases)
    run_pwtfile "teardown"
    run_hook "pre-remove"

    # Clear current symlink if removing the current worktree
    local current_wt=$(get_current_from_symlink 2>/dev/null)
    if [ "$name" = "$current_wt" ]; then
        clear_current_symlink
        echo -e "  ${CYAN}Cleared current symlink${NC}"
    fi

    # Get workspace mode (clone or worktree)
    local workspace_mode=$(get_metadata "$name" "mode")
    workspace_mode="${workspace_mode:-worktree}"  # Default to worktree for backwards compatibility

    # SAFETY: Backup uncommitted changes before removing
    if [ "$has_changes" = true ] && [ -d "$worktree_dir" ]; then
        local backup_dir="$HOME/.pwt/trash"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_name="${name}_${timestamp}"

        mkdir -p "$backup_dir"

        # Save metadata for restore (branch, base, port, etc.)
        local meta_branch=$(get_metadata "$name" "branch" 2>/dev/null || git -C "$worktree_dir" branch --show-current 2>/dev/null || echo "")
        local meta_base=$(get_metadata "$name" "base" 2>/dev/null || echo "")
        local meta_port=$(get_metadata "$name" "port" 2>/dev/null || echo "")
        local meta_desc=$(get_metadata "$name" "description" 2>/dev/null || echo "")
        local meta_project="$CURRENT_PROJECT"

        cat > "$backup_dir/${backup_name}.json" << EOF
{
  "worktree": "$name",
  "branch": "$meta_branch",
  "base": "$meta_base",
  "port": "$meta_port",
  "description": "$meta_desc",
  "project": "$meta_project",
  "timestamp": "$timestamp",
  "date": "$(date -r $(date +%s) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
}
EOF
        echo -e "  ${CYAN}✓ Metadata saved to ~/.pwt/trash/${backup_name}.json${NC}"

        # Try to stash tracked changes
        if git -C "$worktree_dir" stash push -m "pwt-backup-$timestamp" 2>/dev/null; then
            local stash_ref=$(git -C "$worktree_dir" stash list | head -1 | cut -d: -f1)
            if [ -n "$stash_ref" ]; then
                # Export stash to backup dir
                git -C "$worktree_dir" stash show -p "$stash_ref" > "$backup_dir/${backup_name}.patch" 2>/dev/null
                echo -e "  ${CYAN}✓ Tracked changes backed up to ~/.pwt/trash/${backup_name}.patch${NC}"
            fi
        fi

        # Backup untracked files
        local untracked_files=$(git -C "$worktree_dir" ls-files --others --exclude-standard 2>/dev/null)
        if [ -n "$untracked_files" ]; then
            local untracked_backup="$backup_dir/${backup_name}_untracked"
            mkdir -p "$untracked_backup"
            cd "$worktree_dir"
            echo "$untracked_files" | while read -r file; do
                if [ -f "$file" ]; then
                    local dir=$(dirname "$file")
                    mkdir -p "$untracked_backup/$dir"
                    cp "$file" "$untracked_backup/$file" 2>/dev/null
                fi
            done
            echo -e "  ${CYAN}✓ Untracked files backed up to ~/.pwt/trash/${backup_name}_untracked/${NC}"
        fi
    fi

    if [ "$workspace_mode" = "clone" ]; then
        rm -rf "$worktree_dir"
        echo -e "${GREEN}✓ Clone removed${NC}"
    else
        cd "$MAIN_APP"
        git worktree remove "$worktree_dir" --force
        echo -e "${GREEN}✓ Worktree removed${NC}"
    fi

    # Remove metadata
    remove_metadata "$name"
    clear_list_cache  # Invalidate cache so next list won't show removed worktree

    # Delete branch if requested
    if [ "$with_branch" = true ] && [ -n "$branch" ]; then
        # Validate branch exists (locally or remotely)
        local branch_exists=false
        if git rev-parse --verify "$branch" >/dev/null 2>&1; then
            branch_exists=true
        elif git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
            branch_exists=true
        fi

        if [ "$branch_exists" = false ]; then
            echo -e "${YELLOW}Branch '$branch' not found (local or remote)${NC}"
            return 0
        fi

        # Check if branch is merged (unless forcing)
        if [ "$force_branch" = false ]; then
            local target_branch="${DEFAULT_BRANCH:-master}"
            if ! git branch --merged "$target_branch" 2>/dev/null | grep -q "^[[:space:]]*${branch}$"; then
                echo -e "${YELLOW}Branch '$branch' is not merged into $target_branch. Use --force-branch to delete anyway.${NC}"
                return 0
            fi
        fi

        # Delete local branch
        if git rev-parse --verify "$branch" >/dev/null 2>&1; then
            if git branch -D "$branch" 2>/dev/null; then
                echo -e "${GREEN}✓ Local branch deleted: $branch${NC}"
            fi
        fi

        # Delete remote branch
        if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
            if git push origin --delete "$branch" 2>/dev/null; then
                echo -e "${GREEN}✓ Remote branch deleted: origin/$branch${NC}"
            fi
        fi
    fi
}
