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
	local config_file="$config_dir/config"

	# Create config dir if needed
	mkdir -p "$config_dir/hooks"

	case "$key" in
	-h | --help | help)
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
		echo "  branch_prefix  - Prefix for branches (e.g., user/)"
		echo "  base_port      - Base port for allocation (default: 5000)"
		echo "  gateway_port   - Stable gateway proxy port"
		echo "  gateway_host   - Public gateway URL host"
		echo "  workspace_link - Stable symlink kept pointing at the current worktree (for editors)"
		echo ""
		echo "Options:"
		echo "  -h, --help, help    Show this help"
		echo ""
		echo "Config location: ~/.pwt/projects/<project>/config"
		return 0
		;;
	"" | show)
		# Show current config
		echo -e "${BLUE}Project: $CURRENT_PROJECT${NC}"
		echo ""
		echo "Current settings:"
		echo "  main_app:      ${MAIN_APP:-"(auto-detected)"}"
		echo "  worktrees_dir: ${WORKTREES_DIR:-"(auto-detected)"}"
		echo "  branch_prefix: ${BRANCH_PREFIX:-"(none)"}"
		echo "  base_port:     ${BASE_PORT:-5000}"
		local gateway_port
		gateway_port=$(get_project_config "$CURRENT_PROJECT" "gateway_port" || true)
		echo "  gateway_port:  ${gateway_port:-"(not set)"}"
		local gateway_host
		gateway_host=$(get_project_config "$CURRENT_PROJECT" "gateway_host" || true)
		echo "  gateway_host:  ${gateway_host:-localhost}"
		echo ""
		if [ -s "$config_file" ]; then
			echo "Saved overrides ($config_file):"
			cat "$config_file"
		else
			echo "No saved overrides (using auto-detected values)."
		fi
		;;
	main_app | worktrees_dir | branch_prefix | base_port | gateway_port | gateway_host | workspace_link)
		if [ -z "$value" ]; then
			# Show current value
			local current=$(state_get "$config_file" "$key")
			if [ "$key" = "gateway_host" ]; then
				echo "${current:-"localhost"}"
			else
				echo "${current:-"(not set)"}"
			fi
		else
			if [ "$key" = "gateway_host" ]; then
				if ! [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] && ! [[ "$value" =~ ^[A-Za-z0-9]$ ]]; then
					pwt_error "Error: gateway_host must be a hostname or IP without protocol, port, or path"
					return $EXIT_USAGE
				fi
			fi
			# Set value (atomic tmp + mv inside state_set)
			state_set "$config_file" "$key" "$value" && invalidate_project_index
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
		echo "  gateway_port   - Stable gateway proxy port"
		echo "  gateway_host   - Public gateway URL host"
		echo "  workspace_link - Stable symlink kept pointing at the current worktree (for editors)"
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
	"" | list)
		# List all projects
		echo -e "${BLUE}Configured Projects:${NC}"
		echo ""
		if [ -d "$PROJECTS_DIR" ] && [ "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]; then
			for dir in "$PROJECTS_DIR"/*/; do
				[ -d "$dir" ] || continue
				local proj_name=$(basename "$dir")
				local config_file="$dir/config"
				if [ -f "$config_file" ]; then
					local main_app=$(state_get "$config_file" "main_app")
					[ -z "$main_app" ] && main_app=$(state_get "$config_file" "path")
					[ -z "$main_app" ] && main_app="(not set)"
					local prefix=$(state_get "$config_file" "branch_prefix")
					[ -z "$prefix" ] && prefix="(not set)"
					# Get alias if set
					local proj_alias=$(state_get "$config_file" "alias")
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
			pwt_error "Error: Project name required"
			echo "Usage: pwt project init <name>"
			exit 1
		fi
		init_project "$project"
		echo ""
		echo "Edit the config at: $PROJECTS_DIR/$project/config"
		echo "Add hooks in: $PROJECTS_DIR/$project/hooks/"
		;;
	show)
		if [ -z "$project" ]; then
			pwt_error "Error: Project name required"
			echo "Usage: pwt project show <name>"
			exit 1
		fi
		local config_file="$PROJECTS_DIR/$project/config"
		if [ ! -f "$config_file" ]; then
			echo -e "${RED}Project not found: $project${NC}"
			exit 1
		fi
		echo -e "${BLUE}Project: $project${NC}"
		echo ""
		echo "Config:"
		cat "$config_file"
		echo ""
		echo "Hooks:"
		ls -la "$PROJECTS_DIR/$project/hooks/" 2>/dev/null || echo "  (none)"
		;;
	set)
		if [ -z "$project" ] || [ -z "$arg3" ] || [ -z "$arg4" ]; then
			pwt_error "Error: Missing arguments"
			echo "Usage: pwt project set <name> <key> <value>"
			exit 1
		fi
		local config_file="$PROJECTS_DIR/$project/config"
		if [ ! -f "$config_file" ]; then
			echo -e "${RED}Project not found: $project${NC}"
			echo "Use: pwt project init $project"
			exit 1
		fi
		state_set "$config_file" "$arg3" "$arg4" && invalidate_project_index
		echo -e "${GREEN}✓ Updated $project.$arg3 = $arg4${NC}"
		;;
	path)
		if [ -z "$project" ]; then
			pwt_error "Error: Project name required"
			exit 1
		fi
		echo "$PROJECTS_DIR/$project"
		;;
	alias)
		# pwt project alias <project> [alias|--clear]
		local new_alias="$arg3"

		if [ -z "$project" ]; then
			pwt_error "Error: Project name required"
			echo "Usage: pwt project alias <project> [<alias>|--clear]"
			exit 1
		fi

		local config_file="$PROJECTS_DIR/$project/config"
		if [ ! -f "$config_file" ]; then
			echo -e "${RED}Project not found: $project${NC}"
			exit 1
		fi

		if [ -z "$new_alias" ]; then
			# Show current alias
			local current=$(state_get "$config_file" "alias")
			if [ -n "$current" ]; then
				echo "$current"
			else
				echo "(no alias set)"
			fi
		elif [ "$new_alias" = "--clear" ]; then
			# Clear alias
			state_del "$config_file" "alias" && invalidate_project_index
			echo -e "${GREEN}✓ Cleared alias for $project${NC}"
		else
			# Set alias - validate first
			local reserved_commands="list create remove cd server servers gateway test meta port project help version config init show set path alias"
			for cmd in $reserved_commands; do
				if [ "$new_alias" = "$cmd" ]; then
					pwt_error "Error: '$new_alias' is a reserved command name"
					exit 1
				fi
			done
			# Check if alias conflicts with existing project name
			if [ -f "$PROJECTS_DIR/$new_alias/config" ]; then
				pwt_error "Error: '$new_alias' is already a project name"
				exit 1
			fi
			# Check if alias already used by another project
			for cfg in "$PROJECTS_DIR"/*/config; do
				[ -f "$cfg" ] || continue
				local proj_dir=$(dirname "$cfg")
				local proj_name=$(basename "$proj_dir")
				[ "$proj_name" = "$project" ] && continue
				local other_alias=$(state_get "$cfg" "alias")
				if [ "$other_alias" = "$new_alias" ]; then
					pwt_error "Error: Alias '$new_alias' already used by project '$proj_name'"
					exit 1
				fi
			done
			# Set alias
			state_set "$config_file" "alias" "$new_alias" && invalidate_project_index
			echo -e "${GREEN}✓ Set alias '$new_alias' for $project${NC}"
		fi
		;;
	validate | check)
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
	-h | --help | help)
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
		echo "Config location: ~/.pwt/projects/<project>/config"
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
# Command: ports
# Machine-wide port registry: every port pwt has handed out, in every
# project, with conflicts and live status. Ports are a machine resource,
# so "which project owns 8001" is a question no per-project view answers.
# Usage: pwt ports [--json]
cmd_ports() {
	local json=false arg
	for arg in "$@"; do
		case "$arg" in
		--json) json=true ;;
		-h | --help)
			echo "Usage: pwt ports [--json]"
			echo ""
			echo "Show every port pwt has allocated, across all projects."
			echo ""
			echo "Options:"
			echo "  --json      Machine-readable output"
			echo "  -h, --help  Show this help"
			echo ""
			echo "Columns: port, project, worktree, status."
			echo "Status is 'listening' when a server is bound to the port,"
			echo "'system' when a macOS daemon holds it (AirPlay Receiver"
			echo "takes 5000 and 7000), and 'conflict' when two records"
			echo "claim the same port."
			return 0
			;;
		*)
			pwt_error "Unknown option: $arg"
			return "$EXIT_USAGE"
			;;
		esac
	done

	init_metadata
	load_module gateway # port snapshot helpers

	# One record per line: port, project, worktree
	local records
	records=$(
		meta_ports_all
		local cfg base project
		for cfg in "$PWT_PROJECTS_DIR"/*/config; do
			[ -f "$cfg" ] || continue
			base=$(state_get "$cfg" "base_port")
			[ -n "$base" ] || continue
			project="${cfg%/config}"
			project="${project##*/}"
			printf '%s\t%s\t%s\n' "$base" "$project" "@"
		done
	)
	records=$(printf '%s\n' "$records" | grep -v '^$' | sort -n -k1,1)

	# Ports claimed more than once: the thing you actually want flagged
	local dupes
	dupes=$(printf '%s\n' "$records" | awk -F'\t' '{ print $1 }' | sort -n | uniq -d)

	local port project worktree status listening=false conflict=false system=false
	local rows="" any=false has_system=false
	while IFS=$'\t' read -r port project worktree; do
		[ -n "$port" ] || continue
		any=true
		listening=false
		_port_listening_snapshot "$port" && listening=true
		# Occupied, but by a daemon that is not yours: reported apart from
		# "listening" so it never reads as "the server is already up"
		system=false
		if [ "$listening" != true ] && _port_is_system_snapshot "$port"; then
			system=true
			has_system=true
		fi
		conflict=false
		case $'\n'"$dupes"$'\n' in
		*$'\n'"$port"$'\n'*) conflict=true ;;
		esac
		if [ "$json" = true ]; then
			rows="${rows:+$rows,}$(printf '{"port":%s,"project":%s,"worktree":%s,"listening":%s,"system":%s,"conflict":%s}' \
				"$port" "$(json_str "$project")" "$(json_str "$worktree")" "$listening" "$system" "$conflict")"
		else
			status=""
			[ "$listening" = true ] && status="listening"
			[ "$system" = true ] && status="${YELLOW}system${NC}"
			[ "$conflict" = true ] && status="${status:+$status, }${RED}conflict${NC}"
			[ -n "$status" ] || status="-"
			# %b on the status field only: it carries colour escapes,
			# while names must never be escape-interpreted
			rows="${rows}$(printf '%-7s %-18s %-24s %b' "$port" "$project" "$worktree" "$status")"$'\n'
		fi
	done <<<"$records"

	if [ "$json" = true ]; then
		printf '{"ports":[%s]}\n' "$rows"
		return 0
	fi

	if [ "$any" != true ]; then
		echo "No ports allocated yet."
		return 0
	fi

	printf '%-7s %-18s %-24s %s\n' "PORT" "PROJECT" "WORKTREE" "STATUS"
	printf '%-7s %-18s %-24s %s\n' "----" "-------" "--------" "------"
	printf '%s' "$rows"

	if [ "$has_system" = true ]; then
		echo ""
		echo -e "${YELLOW}system:${NC} held by a macOS daemon, not by a server of yours."
		echo "  AirPlay Receiver takes 5000 and 7000: turn it off in System"
		echo "  Settings > General > AirDrop & Handoff, or move the port with"
		echo "  pwt fix-port <worktree>."
	fi

	if [ -n "$dupes" ]; then
		echo ""
		echo -e "${YELLOW}Two records share a port. Fix with:${NC} pwt fix-port <worktree>"
	fi
	return 0
}

cmd_port() {
	local name="$1"

	if [[ "$name" == "-h" || "$name" == "--help" ]]; then
		echo "Usage: pwt port [worktree]"
		echo ""
		echo "Get the port number for a worktree."
		echo ""
		echo "Arguments:"
		echo "  worktree   Target worktree (optional if inside one)"
		echo ""
		echo "Outputs just the port number, useful in scripts:"
		echo "  curl http://localhost:\$(pwt port)"
		echo ""
		echo "Examples:"
		echo "  pwt port               # port for current worktree"
		echo "  pwt port TICKET-123    # port for specific worktree"
		return 0
	fi

	# Normalize: strip trailing slash (from shell completion)
	name="${name%/}"

	# If no name, try to detect from current directory
	if [ -z "$name" ]; then
		local current_dir=$(pwd)
		if [[ "$current_dir" == "$WORKTREES_DIR"/* ]]; then
			name=$(basename "$current_dir")
		else
			pwt_error "Error: Not in a worktree directory"
			exit 1
		fi
	fi

	init_metadata
	local port=$(get_metadata "$name" "port")

	if [ -z "$port" ]; then
		pwt_error "Error: No port found for worktree: $name"
		exit 1
	fi

	echo "$port"
}
