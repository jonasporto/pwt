#!/bin/bash
# ============================================================
# pwt project module
# Project and configuration management
# ============================================================
#
# This module is sourced by bin/pwt when project/config commands are used.
#
# Dependencies:
#   - Requires functions from bin/pwt: init_metadata, load_project_config
#   - Requires variables: PWT_DIR, CURRENT_PROJECT, RED, GREEN, BLUE, YELLOW, NC
#

# Guard against multiple sourcing
[[ -n "${_PWT_PROJECT_LOADED:-}" ]] && return 0
_PWT_PROJECT_LOADED=1

# Command: config
# Configure current project (zero-config override)
cmd_config() {
    local key="$1"
    local value="$2"

    # Ensure project is detected
    if [ -z "$CURRENT_PROJECT" ]; then
        pwt_error "Error: No project detected"
        echo "Run from inside a git repository."
        exit 1
    fi

    local config_dir="$PWT_PROJECTS_DIR/$CURRENT_PROJECT"
    local config_file="$config_dir/config.json"

    # Create config dir if needed
    mkdir -p "$config_dir/hooks"

    # Initialize config file if needed
    if [ ! -f "$config_file" ]; then
        echo "{}" > "$config_file"
    fi

    case "$key" in
        -h|--help|help)
            echo "Usage: pwt config [key] [value]"
            echo ""
            echo "View or set project configuration."
            echo ""
            echo "Commands:"
            echo "  show                 Show all settings (default)"
            echo "  <key>                Show value for key"
            echo "  <key> <value>        Set value for key"
            echo ""
            echo "Keys:"
            echo "  main_app       - Path to main project"
            echo "  worktrees_dir  - Path to worktrees directory"
            echo "  branch_prefix  - Prefix for branches (e.g., gl/)"
            echo "  base_port      - Base port for allocation (default: 5000)"
            echo ""
            echo "Options:"
            echo "  -h, --help, help    Show this help"
            echo ""
            echo "Config location: ~/.pwt/projects/<project>/config.json"
            return 0
            ;;
        ""|show)
            # Show current config
            echo -e "${BLUE}Project: $CURRENT_PROJECT${NC}"
            echo ""
            echo "Current settings:"
            echo "  main_app:      ${MAIN_APP:-"(auto-detected)"}"
            echo "  worktrees_dir: ${WORKTREES_DIR:-"(auto-detected)"}"
            echo "  branch_prefix: ${BRANCH_PREFIX:-"(none)"}"
            echo "  base_port:     ${BASE_PORT:-5000}"
            echo ""
            if [ -f "$config_file" ] && [ "$(cat "$config_file")" != "{}" ]; then
                echo "Saved overrides ($config_file):"
                jq '.' "$config_file"
            else
                echo "No saved overrides (using auto-detected values)."
            fi
            ;;
        main_app|worktrees_dir|branch_prefix|base_port)
            if [ -z "$value" ]; then
                # Show current value
                local current=$(jq -r ".$key // empty" "$config_file" 2>/dev/null)
                echo "${current:-"(not set)"}"
            else
                # Set value (create tmp in same dir for atomic mv)
                local tmp_file
                tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
                jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
                echo -e "${GREEN}✓ Set $key = $value${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Unknown config key: $key${NC}"
            echo ""
            echo "Available keys:"
            echo "  main_app       - Path to main project"
            echo "  worktrees_dir  - Path to worktrees directory"
            echo "  branch_prefix  - Prefix for branches (e.g., user/)"
            echo "  base_port      - Base port for allocation"
            exit 1
            ;;
    esac
}

# Command: project
# Manage project configurations
cmd_project() {
    local action="$1"
    local project="$2"
    local arg3="$3"
    local arg4="$4"

    init_metadata

    case "$action" in
        ""|list)
            # List all projects
            echo -e "${BLUE}Configured Projects:${NC}"
            echo ""
            if [ -d "$PROJECTS_DIR" ] && [ "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]; then
                for dir in "$PROJECTS_DIR"/*/; do
                    [ -d "$dir" ] || continue
                    local proj_name=$(basename "$dir")
                    local config_file="$dir/config.json"
                    if [ -f "$config_file" ]; then
                        local main_app=$(jq -r '.main_app // "(not set)"' "$config_file")
                        local prefix=$(jq -r '.branch_prefix // "(not set)"' "$config_file")
                        # Get alias if set
                        local proj_alias=$(jq -r '.alias // empty' "$config_file")
                        if [ -n "$proj_alias" ]; then
                            echo -e "  ${GREEN}$proj_name${NC} (${CYAN}$proj_alias${NC})"
                        else
                            echo -e "  ${GREEN}$proj_name${NC}"
                        fi
                        echo "    main_app: $main_app"
                        echo "    branch_prefix: $prefix"
                        # Count hooks
                        local hook_count=$(ls "$dir/hooks" 2>/dev/null | wc -l | tr -d ' ')
                        if [ "$hook_count" -gt 0 ]; then
                            echo "    hooks: $hook_count"
                        fi
                        echo ""
                    fi
                done
            else
                echo "  No projects configured yet."
                echo ""
                echo "  Use: pwt project init <name>"
            fi
            ;;
        init)
            if [ -z "$project" ]; then
                echo -e "${RED}Error: Project name required${NC}"
                echo "Usage: pwt project init <name>"
                exit 1
            fi
            init_project "$project"
            echo ""
            echo "Edit the config at: $PROJECTS_DIR/$project/config.json"
            echo "Add hooks in: $PROJECTS_DIR/$project/hooks/"
            ;;
        show)
            if [ -z "$project" ]; then
                echo -e "${RED}Error: Project name required${NC}"
                echo "Usage: pwt project show <name>"
                exit 1
            fi
            local config_file="$PROJECTS_DIR/$project/config.json"
            if [ ! -f "$config_file" ]; then
                echo -e "${RED}Project not found: $project${NC}"
                exit 1
            fi
            echo -e "${BLUE}Project: $project${NC}"
            echo ""
            echo "Config:"
            jq '.' "$config_file"
            echo ""
            echo "Hooks:"
            ls -la "$PROJECTS_DIR/$project/hooks/" 2>/dev/null || echo "  (none)"
            ;;
        set)
            if [ -z "$project" ] || [ -z "$arg3" ] || [ -z "$arg4" ]; then
                echo -e "${RED}Error: Missing arguments${NC}"
                echo "Usage: pwt project set <name> <key> <value>"
                exit 1
            fi
            local config_file="$PROJECTS_DIR/$project/config.json"
            if [ ! -f "$config_file" ]; then
                echo -e "${RED}Project not found: $project${NC}"
                echo "Use: pwt project init $project"
                exit 1
            fi
            # Create tmp in same dir for atomic mv
            local tmp_file
            tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
            jq --arg key "$arg3" --arg value "$arg4" '.[$key] = $value' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
            echo -e "${GREEN}✓ Updated $project.$arg3 = $arg4${NC}"
            ;;
        path)
            if [ -z "$project" ]; then
                echo -e "${RED}Error: Project name required${NC}"
                exit 1
            fi
            echo "$PROJECTS_DIR/$project"
            ;;
        alias)
            # pwt project alias <project> [alias|--clear]
            local new_alias="$arg3"

            if [ -z "$project" ]; then
                echo -e "${RED}Error: Project name required${NC}"
                echo "Usage: pwt project alias <project> [<alias>|--clear]"
                exit 1
            fi

            local config_file="$PROJECTS_DIR/$project/config.json"
            if [ ! -f "$config_file" ]; then
                echo -e "${RED}Project not found: $project${NC}"
                exit 1
            fi

            if [ -z "$new_alias" ]; then
                # Show current alias
                local current=$(jq -r '.alias // empty' "$config_file")
                if [ -n "$current" ]; then
                    echo "$current"
                else
                    echo "(no alias set)"
                fi
            elif [ "$new_alias" = "--clear" ]; then
                # Clear alias
                local tmp_file
                tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
                jq 'del(.alias)' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
                echo -e "${GREEN}✓ Cleared alias for $project${NC}"
            else
                # Set alias - validate first
                local reserved_commands="list create remove cd server test meta port project help version config init show set path alias"
                for cmd in $reserved_commands; do
                    if [ "$new_alias" = "$cmd" ]; then
                        echo -e "${RED}Error: '$new_alias' is a reserved command name${NC}"
                        exit 1
                    fi
                done
                # Check if alias conflicts with existing project name
                if [ -f "$PROJECTS_DIR/$new_alias/config.json" ]; then
                    echo -e "${RED}Error: '$new_alias' is already a project name${NC}"
                    exit 1
                fi
                # Check if alias already used by another project
                for cfg in "$PROJECTS_DIR"/*/config.json; do
                    [ -f "$cfg" ] || continue
                    local proj_dir=$(dirname "$cfg")
                    local proj_name=$(basename "$proj_dir")
                    [ "$proj_name" = "$project" ] && continue
                    local other_alias=$(jq -r '.alias // empty' "$cfg")
                    if [ "$other_alias" = "$new_alias" ]; then
                        echo -e "${RED}Error: Alias '$new_alias' already used by project '$proj_name'${NC}"
                        exit 1
                    fi
                done
                # Set alias
                local tmp_file
                tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
                jq --arg alias "$new_alias" '.alias = $alias' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
                echo -e "${GREEN}✓ Set alias '$new_alias' for $project${NC}"
            fi
            ;;
        validate|check)
            # Validate current project setup
            local errors=0
            local warnings=0

            echo -e "${BLUE}Validating project: $CURRENT_PROJECT${NC}"
            echo ""

            # Check main_app exists
            if [ -d "$MAIN_APP" ]; then
                echo -e "  ${GREEN}✓${NC} main_app exists: $MAIN_APP"
            else
                echo -e "  ${RED}✗${NC} main_app not found: $MAIN_APP"
                ((errors++))
            fi

            # Check worktrees_dir exists
            if [ -d "$WORKTREES_DIR" ]; then
                echo -e "  ${GREEN}✓${NC} worktrees_dir exists: $WORKTREES_DIR"
            else
                echo -e "  ${YELLOW}!${NC} worktrees_dir not found: $WORKTREES_DIR"
                echo -e "    (will be created on first worktree)"
                ((warnings++))
            fi

            # Check Pwtfile exists
            local pwtfile="$MAIN_APP/Pwtfile"
            if [ -f "$pwtfile" ]; then
                echo -e "  ${GREEN}✓${NC} Pwtfile found"
            else
                echo -e "  ${YELLOW}!${NC} No Pwtfile (optional)"
                ((warnings++))
            fi

            # Check md-docs symlink in main app
            local md_docs_link="$MAIN_APP/md-docs"
            if [ -L "$md_docs_link" ]; then
                if [ -d "$md_docs_link" ]; then
                    echo -e "  ${GREEN}✓${NC} md-docs symlink valid"
                else
                    echo -e "  ${RED}✗${NC} md-docs symlink broken"
                    ((errors++))
                fi
            else
                echo -e "  ${YELLOW}!${NC} No md-docs symlink (optional)"
                ((warnings++))
            fi

            # Check .env exists in main app
            if [ -f "$MAIN_APP/.env" ]; then
                echo -e "  ${GREEN}✓${NC} .env file found"
            else
                echo -e "  ${YELLOW}!${NC} No .env file"
                ((warnings++))
            fi

            # Check git repo
            if git -C "$MAIN_APP" rev-parse --git-dir >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Git repository"
            else
                echo -e "  ${RED}✗${NC} Not a git repository"
                ((errors++))
            fi

            echo ""
            if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
                echo -e "${GREEN}All checks passed!${NC}"
            elif [ $errors -eq 0 ]; then
                echo -e "${YELLOW}$warnings warning(s), no errors${NC}"
            else
                echo -e "${RED}$errors error(s), $warnings warning(s)${NC}"
                exit 1
            fi
            ;;
        -h|--help|help)
            echo "Usage: pwt project [command] [args]"
            echo ""
            echo "Manage project configurations."
            echo ""
            echo "Commands:"
            echo "  list                           List all configured projects (default)"
            echo "  init <name>                    Initialize a new project config"
            echo "  show <name>                    Show project config and hooks"
            echo "  set <name> <key> <value>       Update project config value"
            echo "  path <name>                    Print project config directory path"
            echo "  alias <name> [alias|--clear]   Get/set/clear project alias"
            echo "  validate                       Validate current project setup"
            echo ""
            echo "Options:"
            echo "  -h, --help, help    Show this help"
            echo ""
            echo "Config location: ~/.pwt/projects/<project>/config.json"
            echo "Hooks location: ~/.pwt/projects/<project>/hooks/"
            return 0
            ;;
        *)
            echo -e "${RED}Unknown action: $action${NC}"
            echo "Usage: pwt project [list|init|show|set|path|alias]"
            echo ""
            echo "Commands:"
            echo "  list                    - List all configured projects"
            echo "  init <name>             - Initialize a new project config"
            echo "  show <name>             - Show project config and hooks"
            echo "  set <name> <k> <v>      - Update project config value"
            echo "  path <name>             - Print project config directory path"
            echo "  alias <name> [a|--clear] - Get/set/clear project alias"
            exit 1
            ;;
    esac
}
# Command: port
# Get port for a worktree
cmd_port() {
    local name="$1"

    # If no name, try to detect from current directory
    if [ -z "$name" ]; then
        local current_dir=$(pwd)
        if [[ "$current_dir" == "$WORKTREES_DIR"/* ]]; then
            name=$(basename "$current_dir")
        else
            echo -e "${RED}Error: Not in a worktree directory${NC}" >&2
            exit 1
        fi
    fi

    init_metadata
    local port=$(get_metadata "$name" "port")

    if [ -z "$port" ]; then
        echo -e "${RED}Error: No port found for worktree: $name${NC}" >&2
        exit 1
    fi

    echo "$port"
}
