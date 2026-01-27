#!/bin/bash
# ============================================================
# pwt claude module
# Claude Code status line integration
# ============================================================
#
# This module is sourced by bin/pwt when claude-setup command is used.
#
# Dependencies:
#   - Requires functions from bin/pwt: detect_project, load_project_config
#   - Requires variables: PWT_DIR, CURRENT_PROJECT, RED, GREEN, BLUE, YELLOW, NC
#

# Guard against multiple sourcing
[[ -n "${_PWT_CLAUDE_LOADED:-}" ]] && return 0
_PWT_CLAUDE_LOADED=1

# Command: claude-setup
# Install Claude Code status line integration for pwt
cmd_claude_setup() {
    local action="${1:-install}"
    local claude_dir="$HOME/.claude"
    local script_file="$claude_dir/statusline-command.sh"
    local config_file="$PWT_DIR/claude-statusline.json"
    local default_format='[{worktree}] {project} ({branch}) [{server}] {arrow}'

    case "$action" in
        -h|--help|help)
            echo "Usage: pwt claude-setup [action]"
            echo ""
            echo "Manage Claude Code status line integration."
            echo ""
            echo "Actions:"
            echo "  install              Install/update status line script (default)"
            echo "  vars                 Show all available variables and colors"
            echo "  format [fmt]         Show or set global format"
            echo "  format --project [fmt]  Set format for current project only"
            echo "  preview              Preview status line with current settings"
            echo "  test                 Run color and template engine tests"
            echo "  toggle               Toggle status line on/off globally"
            echo "  toggle --session     Toggle for current session only"
            echo "  on | off             Enable/disable globally"
            echo "  on|off --session     Show command for session toggle"
            echo "  pwt-only [on|off]    Only show in pwt projects/worktrees"
            echo "  reset                Reset to default configuration"
            echo ""
            echo "Format Template:"
            echo "  Use {variable} placeholders with any text around them."
            echo "  Run 'pwt claude-setup vars' to see all variables."
            echo ""
            echo "Priority: Project format > Global format > Default"
            echo ""
            echo "Examples:"
            echo "  pwt claude-setup                              # Install"
            echo "  pwt claude-setup vars                         # List variables"
            echo "  pwt claude-setup format                       # Show formats"
            echo "  pwt claude-setup format '{project} ({branch}) {arrow}'"
            echo "  pwt claude-setup format --project '{project} {arrow}'  # This project only"
            echo "  pwt claude-setup preview                      # Test output"
            return 0
            ;;

        vars)
            echo "Available variables for status line format:"
            echo ""
            echo "  {worktree}   Worktree name (e.g., 'mobile-ux-fixes')"
            echo "  {project}    Project name (e.g., 'dropflow-app')"
            echo "  {branch}     Git branch name"
            echo "  {server}     Server URL if running (e.g., 'localhost:4001')"
            echo "  {port}       Just the port number (e.g., '4001')"
            echo "  {arrow}      Arrow symbol (default: ❯)"
            echo ""
            echo "Named Colors:"
            echo "  {magenta:...}   Magenta text"
            echo "  {cyan:...}      Cyan text"
            echo "  {yellow:...}    Yellow text"
            echo "  {green:...}     Green text"
            echo "  {blue:...}      Blue text"
            echo "  {red:...}       Red text"
            echo "  {dim:...}       Dimmed text"
            echo "  {bold:...}      Bold text"
            echo ""
            echo "Custom Colors (24-bit true color):"
            echo "  {rgb:R,G,B:...}    RGB values 0-255 (e.g., {rgb:255,100,0:text})"
            echo "  {#RRGGBB:...}      Hex color (e.g., {#FF6400:text})"
            echo ""
            echo "Conditionals (show only if value exists):"
            echo "  {?worktree:[...]}   Show [...] only if worktree exists"
            echo "  {?server:[...]}     Show [...] only if server is running"
            echo "  {?branch:(...)}     Show (...) only if branch exists"
            echo ""
            echo "Default format:"
            echo "  $default_format"
            echo ""
            echo "Custom Variables (from Pwtfile):"
            echo "  Static:   CLAUDE_ENV=\"staging\"     -> use as {env}"
            echo "  Dynamic:  claude_env() { ... }      -> use as {env}"
            echo ""
            echo "  Available in functions: \$PWT_WORKTREE, \$PWT_PROJECT, \$PWT_PORT, \$PWT_BRANCH"
            echo ""
            echo "Example formats:"
            echo "  '{project} {arrow}'                           # Minimal"
            echo "  '{?worktree:[{worktree}] }{project} {arrow}'  # Conditional worktree"
            echo "  '{project}/{worktree} ({branch}) {arrow}'     # Slash separator"
            echo "  '{cyan:{project}} {yellow:({branch})} {arrow}' # Explicit colors"
            echo "  '{project} [{env}] {arrow}'                   # Custom var from Pwtfile"
            return 0
            ;;

        format)
            local scope="${2:-}"
            local new_format="${3:-}"

            # Check if second arg is a format (not --project)
            if [ -n "$scope" ] && [[ "$scope" != "--project" ]]; then
                new_format="$scope"
                scope=""
            fi

            if [ "$scope" = "--project" ]; then
                # Project-specific format
                if [ -z "$CURRENT_PROJECT" ]; then
                    echo -e "${RED}Error: No project detected. Run from inside a project.${NC}"
                    return 1
                fi

                local proj_config="$PWT_PROJECTS_DIR/$CURRENT_PROJECT/config.json"
                mkdir -p "$(dirname "$proj_config")"
                [ ! -f "$proj_config" ] && echo '{}' > "$proj_config"

                if [ -n "$new_format" ]; then
                    local tmp=$(mktemp)
                    jq --arg fmt "$new_format" '.claude_format = $fmt' "$proj_config" > "$tmp" && mv "$tmp" "$proj_config"
                    echo -e "${GREEN}✓ Project format set for $CURRENT_PROJECT${NC}"
                    echo "  $new_format"
                else
                    local proj_format=$(jq -r '.claude_format // ""' "$proj_config" 2>/dev/null)
                    if [ -n "$proj_format" ]; then
                        echo "Project format ($CURRENT_PROJECT):"
                        echo "  $proj_format"
                    else
                        echo "No project-specific format for $CURRENT_PROJECT"
                        echo "Using global format: $default_format"
                    fi
                fi
                echo ""
                echo "Run 'pwt claude-setup install' to apply."
            elif [ -n "$new_format" ]; then
                # Set global format
                [ ! -f "$config_file" ] && echo '{}' > "$config_file"
                local tmp=$(mktemp)
                jq --arg fmt "$new_format" '.format = $fmt' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
                echo -e "${GREEN}✓ Global format set${NC}"
                echo "  $new_format"
                echo ""
                echo "Run 'pwt claude-setup install' to apply."
            else
                # Show current format
                echo "Global format:"
                local current_format="$default_format"
                if [ -f "$config_file" ]; then
                    current_format=$(jq -r '.format // ""' "$config_file")
                    [ -z "$current_format" ] && current_format="$default_format"
                fi
                echo "  $current_format"

                # Show project format if inside a project
                if [ -n "$CURRENT_PROJECT" ]; then
                    local proj_config="$PWT_PROJECTS_DIR/$CURRENT_PROJECT/config.json"
                    if [ -f "$proj_config" ]; then
                        local proj_format=$(jq -r '.claude_format // ""' "$proj_config" 2>/dev/null)
                        if [ -n "$proj_format" ]; then
                            echo ""
                            echo "Project format ($CURRENT_PROJECT):"
                            echo "  $proj_format"
                        fi
                    fi
                fi
                echo ""
                echo "To change global:  pwt claude-setup format '<format>'"
                echo "To change project: pwt claude-setup format --project '<format>'"
                echo "See variables:     pwt claude-setup vars"
            fi
            return 0
            ;;

        preview)
            # Generate preview with current directory
            local current_format="$default_format"
            if [ -f "$config_file" ]; then
                current_format=$(jq -r '.format // ""' "$config_file")
                [ -z "$current_format" ] && current_format="$default_format"
            fi

            local cwd=$(pwd)
            local worktree_name="" project_name=""

            if [[ "$cwd" =~ ([^/]+)-worktrees/([^/]+) ]]; then
                project_name="${BASH_REMATCH[1]}"
                worktree_name="${BASH_REMATCH[2]}"
            elif [[ "$cwd" =~ \.pwt/([^/]+) ]]; then
                worktree_name="${BASH_REMATCH[1]}"
            fi
            [ -z "$project_name" ] && project_name=$(basename "$cwd")

            local branch=""
            if git rev-parse --git-dir >/dev/null 2>&1; then
                branch=$(git branch --show-current 2>/dev/null)
            fi

            local port="" server=""
            if [ -n "$worktree_name" ] && [ -f "$PWT_META_FILE" ]; then
                port=$(jq -r --arg wt "$worktree_name" '.[] | .[$wt]? | select(.) | .port // empty' "$PWT_META_FILE" 2>/dev/null | head -1)
                if [ -n "$port" ] && lsof -ti :$port -sTCP:LISTEN >/dev/null 2>&1; then
                    server="localhost:$port"
                fi
            fi

            echo "Preview with current directory:"
            echo "  worktree: ${worktree_name:-<none>}"
            echo "  project:  $project_name"
            echo "  branch:   ${branch:-<none>}"
            echo "  server:   ${server:-<not running>}"
            echo "  port:     ${port:-<none>}"
            echo ""
            echo "Format: $current_format"
            echo ""
            echo -n "Output: "
            # Simple preview (without full template engine)
            local output="$current_format"
            output="${output//\{worktree\}/$worktree_name}"
            output="${output//\{project\}/$project_name}"
            output="${output//\{branch\}/$branch}"
            output="${output//\{server\}/$server}"
            output="${output//\{port\}/$port}"
            output="${output//\{arrow\}/❯}"
            echo -e "$output"
            return 0
            ;;

        reset)
            rm -f "$config_file"
            echo -e "${GREEN}✓ Configuration reset to defaults${NC}"
            echo "Run 'pwt claude-setup install' to apply."
            return 0
            ;;

        test)
            local test_script="$PWT_DIR/tests/statusline-test.sh"
            if [ -f "$test_script" ]; then
                bash "$test_script"
            else
                echo -e "${RED}Test script not found at $test_script${NC}"
                echo "Tests may not be installed yet."
                return 1
            fi
            return 0
            ;;

        toggle)
            local scope="${2:-}"
            if [ "$scope" = "--session" ]; then
                # Session toggle - just show the command to run
                if [ "${PWT_STATUSLINE_OFF:-}" = "1" ]; then
                    echo -e "${GREEN}To enable for this session:${NC}"
                    echo "  unset PWT_STATUSLINE_OFF"
                else
                    echo -e "${YELLOW}To disable for this session:${NC}"
                    echo "  export PWT_STATUSLINE_OFF=1"
                fi
                echo ""
                echo "Add to your shell to persist: ~/.zshrc or ~/.bashrc"
            else
                # Global toggle
                [ ! -f "$config_file" ] && echo '{}' > "$config_file"
                local current=$(jq -r 'if has("enabled") then .enabled else true end' "$config_file")
                local new_state="true"
                [ "$current" = "true" ] && new_state="false"
                local tmp=$(mktemp)
                jq --argjson enabled "$new_state" '.enabled = $enabled' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
                if [ "$new_state" = "true" ]; then
                    echo -e "${GREEN}✓ Status line enabled (all sessions)${NC}"
                else
                    echo -e "${YELLOW}✓ Status line disabled (all sessions)${NC}"
                fi
                echo "Run 'pwt claude-setup install' to apply."
            fi
            return 0
            ;;

        on)
            local scope="${2:-}"
            if [ "$scope" = "--session" ]; then
                echo -e "${GREEN}To enable for this session:${NC}"
                echo "  unset PWT_STATUSLINE_OFF"
            else
                [ ! -f "$config_file" ] && echo '{}' > "$config_file"
                local tmp=$(mktemp)
                jq '.enabled = true' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
                echo -e "${GREEN}✓ Status line enabled (all sessions)${NC}"
                echo "Run 'pwt claude-setup install' to apply."
            fi
            return 0
            ;;

        off)
            local scope="${2:-}"
            if [ "$scope" = "--session" ]; then
                echo -e "${YELLOW}To disable for this session:${NC}"
                echo "  export PWT_STATUSLINE_OFF=1"
            else
                [ ! -f "$config_file" ] && echo '{}' > "$config_file"
                local tmp=$(mktemp)
                jq '.enabled = false' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
                echo -e "${YELLOW}✓ Status line disabled (all sessions)${NC}"
                echo "Run 'pwt claude-setup install' to apply."
            fi
            return 0
            ;;

        pwt-only)
            local state="${2:-}"
            [ ! -f "$config_file" ] && echo '{}' > "$config_file"
            if [ -z "$state" ]; then
                # Show current state
                local current=$(jq -r '.pwt_only // false' "$config_file")
                if [ "$current" = "true" ]; then
                    echo "pwt-only: ${GREEN}on${NC} (status line only shows in pwt projects/worktrees)"
                else
                    echo "pwt-only: ${YELLOW}off${NC} (status line shows everywhere)"
                fi
            elif [ "$state" = "on" ]; then
                local tmp=$(mktemp)
                jq '.pwt_only = true' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
                echo -e "${GREEN}✓ pwt-only enabled${NC}"
                echo "Status line will only show in pwt projects/worktrees."
                echo "Run 'pwt claude-setup install' to apply."
            elif [ "$state" = "off" ]; then
                local tmp=$(mktemp)
                jq '.pwt_only = false' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
                echo -e "${YELLOW}✓ pwt-only disabled${NC}"
                echo "Status line will show in all directories."
                echo "Run 'pwt claude-setup install' to apply."
            else
                echo -e "${RED}Usage: pwt claude-setup pwt-only [on|off]${NC}"
                return 1
            fi
            return 0
            ;;

        install|"")
            ;;

        *)
            echo -e "${RED}Unknown action: $action${NC}"
            echo "Run 'pwt claude-setup help' for usage"
            return 1
            ;;
    esac

    # Create .claude directory if needed
    mkdir -p "$claude_dir"

    # Read config
    local format="$default_format"
    if [ -f "$config_file" ]; then
        local cfg_format=$(jq -r '.format // ""' "$config_file")
        [ -n "$cfg_format" ] && format="$cfg_format"
    fi

    # Write the status line script with template engine
    cat > "$script_file" << 'STATUSLINE_EOF'
#!/bin/bash
# Claude Code Status Line for pwt (Power Worktrees)
# Generated by: pwt claude-setup
# Docs: pwt claude-setup help

DEFAULT_FORMAT='__FORMAT_PLACEHOLDER__'
PWT_DIR="${PWT_DIR:-$HOME/.pwt}"

# Check if disabled via environment (session toggle)
[ "${PWT_STATUSLINE_OFF:-}" = "1" ] && exit 0

# Check if status line is enabled (global toggle)
config_file="$PWT_DIR/claude-statusline.json"
if [ -f "$config_file" ]; then
  enabled=$(jq -r 'if has("enabled") then .enabled else true end' "$config_file" 2>/dev/null)
  [ "$enabled" = "false" ] && exit 0
fi

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$cwd" ] && cwd=$(pwd)

# Detect worktree and project
worktree="" project="" is_pwt_context=false

# Fast path: check common patterns
if echo "$cwd" | grep -q '\-worktrees/'; then
  project=$(echo "$cwd" | perl -ne 'print $1 if /\/([^\/]+)-worktrees\//')
  worktree=$(echo "$cwd" | perl -ne 'print $1 if /-worktrees\/([^\/]+)/')
  is_pwt_context=true
elif echo "$cwd" | grep -q '\.pwt/'; then
  worktree=$(echo "$cwd" | perl -ne 'print $1 if /\.pwt\/([^\/]+)/')
  is_pwt_context=true
fi

# Fallback: check against configured projects
if [ "$is_pwt_context" = "false" ] && [ -d "$PWT_DIR/projects" ]; then
  for proj_config in "$PWT_DIR/projects"/*/config.json; do
    [ -f "$proj_config" ] || continue
    proj_name=$(basename "$(dirname "$proj_config")")
    proj_path=$(jq -r '.path // empty' "$proj_config" 2>/dev/null)
    proj_wt_dir=$(jq -r '.worktrees_dir // empty' "$proj_config" 2>/dev/null)

    # Check if cwd is inside worktrees_dir
    if [ -n "$proj_wt_dir" ] && [[ "$cwd" == "$proj_wt_dir"/* ]]; then
      project="$proj_name"
      worktree=$(echo "$cwd" | sed "s|^$proj_wt_dir/||" | cut -d/ -f1)
      is_pwt_context=true
      break
    fi

    # Infer main path from worktrees_dir if not configured (remove -worktrees suffix)
    if [ -z "$proj_path" ] && [ -n "$proj_wt_dir" ]; then
      proj_path="${proj_wt_dir%-worktrees}"
    fi

    # Check if cwd is the main project path (or inside it)
    if [ -n "$proj_path" ] && [[ "$cwd" == "$proj_path" || "$cwd" == "$proj_path"/* ]]; then
      project="$proj_name"
      worktree="@"
      is_pwt_context=true
      break
    fi
  done
fi

[ -z "$project" ] && project=$(basename "$cwd")

# Check pwt-only mode: if enabled, only show status in pwt projects/worktrees
if [ -f "$config_file" ]; then
  pwt_only=$(jq -r '.pwt_only // false' "$config_file" 2>/dev/null)
  [ "$pwt_only" = "true" ] && [ "$is_pwt_context" = "false" ] && exit 0
fi

# Check for format: global config first, then project-specific
FORMAT="$DEFAULT_FORMAT"
global_config="$PWT_DIR/claude-statusline.json"
if [ -f "$global_config" ]; then
  global_format=$(jq -r '.format // ""' "$global_config" 2>/dev/null)
  [ -n "$global_format" ] && FORMAT="$global_format"
fi
project_config="$PWT_DIR/projects/$project/config.json"
if [ -f "$project_config" ]; then
  proj_format=$(jq -r '.claude_format // ""' "$project_config" 2>/dev/null)
  [ -n "$proj_format" ] && FORMAT="$proj_format"
fi

# Git branch
branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

# Server port from pwt metadata
port="" server=""
PWT_META="${PWT_DIR:-$HOME/.pwt}/meta.json"
if [ -n "$worktree" ] && [ -f "$PWT_META" ]; then
  port=$(jq -r --arg wt "$worktree" '.[] | .[$wt]? | select(.) | .port // empty' "$PWT_META" 2>/dev/null | head -1)
  if [ -n "$port" ] && lsof -ti :$port -sTCP:LISTEN >/dev/null 2>&1; then
    server="localhost:$port"
  else
    port=""
  fi
fi

# Fallback: Rails pid file
if [ -z "$server" ] && [ -f "$cwd/tmp/pids/server.pid" ]; then
  pid=$(cat "$cwd/tmp/pids/server.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    port=$(lsof -Pan -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null | grep -oE ':\d+' | head -1 | tr -d ':')
    [ -n "$port" ] && server="localhost:$port"
  fi
fi

# Custom variables from Pwtfile
# Supports:
#   CLAUDE_VAR="static value"     -> {var}
#   claude_var() { echo "dynamic"; }  -> {var} (called each time)
#
# Find Pwtfile: prefer worktree's own Pwtfile, fallback to main app
main_app=""
pwtfile=""
if [ -f "$cwd/Pwtfile" ]; then
  # Worktree has its own Pwtfile
  pwtfile="$cwd/Pwtfile"
  main_app="$cwd"
elif echo "$cwd" | grep -q '\-worktrees/'; then
  # Fallback to main app Pwtfile
  main_app=$(echo "$cwd" | perl -ne 'print $1 if /(.+)-worktrees\//')
  [ -f "$main_app/Pwtfile" ] && pwtfile="$main_app/Pwtfile"
fi

# Will hold custom var replacements as "name=value" lines
custom_vars_data=""
if [ -n "$pwtfile" ] && [ -f "$pwtfile" ]; then
  # Source Pwtfile in subshell to get variables and functions
  custom_vars_data=$(
    cd "$main_app" 2>/dev/null || true
    # Export context vars that Pwtfile might need
    export PWT_WORKTREE="$worktree"
    export PWT_PROJECT="$project"
    export PWT_PORT="$port"
    export PWT_BRANCH="$branch"

    # Source the Pwtfile
    source "$pwtfile" 2>/dev/null

    # Output CLAUDE_* variables (static) - use set to see all vars
    set | grep '^CLAUDE_' | while IFS='=' read -r key value; do
      var_name=$(echo "${key#CLAUDE_}" | tr '[:upper:]' '[:lower:]')
      # Remove quotes
      value="${value#\'}"
      value="${value%\'}"
      echo "$var_name=$value"
    done

    # Call claude_* functions (dynamic)
    declare -F 2>/dev/null | awk '{print $3}' | grep '^claude_' | while read -r func; do
      var_name="${func#claude_}"
      value=$("$func" 2>/dev/null)
      [ -n "$value" ] && echo "$var_name=$value"
    done
  )
fi

# Template engine
output="$FORMAT"

# Process conditionals: {?var:content} -> show content only if var has value
while [[ "$output" =~ \{\?([a-z]+):([^}]*)\} ]]; do
  var_name="${BASH_REMATCH[1]}"
  content="${BASH_REMATCH[2]}"
  var_value="${!var_name}"

  if [ -n "$var_value" ]; then
    # Replace {var} inside content
    content="${content//\{$var_name\}/$var_value}"
    output="${output/\{?$var_name:$content\}/$content}"
  else
    output="${output/\{?$var_name:*\}/}"
  fi
done

# Replace simple variables first (before colors, so colors can wrap them)
output="${output//\{worktree\}/$worktree}"
output="${output//\{project\}/$project}"
output="${output//\{branch\}/$branch}"
output="${output//\{port\}/$port}"
output="${output//\{arrow\}/❯}"

# Replace custom variables from Pwtfile
if [ -n "$custom_vars_data" ]; then
  while IFS='=' read -r var_name var_value; do
    [ -n "$var_name" ] && output="${output//\{$var_name\}/$var_value}"
  done <<< "$custom_vars_data"
fi

# Server with clickable link
if [ -n "$server" ]; then
  url="http://$server"
  link_start=$'\e]8;;'"${url}"$'\e\\'
  link_end=$'\e]8;;\e\\'
  server_linked="${link_start}${server}${link_end}"
  output="${output//\{server\}/$server_linked}"
else
  output="${output//\{server\}/}"
fi

# Process colors: {color:content}, {rgb:R,G,B:content}, {#RRGGBB:content}
# Using perl for reliable regex
if command -v perl >/dev/null 2>&1; then
  output=$(echo "$output" | perl -pe '
    # Named colors
    s/\{magenta:([^}]*)\}/\033[35m$1\033[0m/g;
    s/\{cyan:([^}]*)\}/\033[36m$1\033[0m/g;
    s/\{yellow:([^}]*)\}/\033[33m$1\033[0m/g;
    s/\{green:([^}]*)\}/\033[32m$1\033[0m/g;
    s/\{blue:([^}]*)\}/\033[34m$1\033[0m/g;
    s/\{red:([^}]*)\}/\033[31m$1\033[0m/g;
    s/\{dim:([^}]*)\}/\033[2m$1\033[0m/g;
    s/\{bold:([^}]*)\}/\033[1m$1\033[0m/g;
    # RGB: {rgb:R,G,B:content}
    s/\{rgb:(\d+),(\d+),(\d+):([^}]*)\}/\033[38;2;$1;$2;$3m$4\033[0m/g;
    # Hex: {#RRGGBB:content}
    s/\{#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2}):([^}]*)\}/sprintf("\033[38;2;%d;%d;%dm%s\033[0m", hex($1), hex($2), hex($3), $4)/ge;
  ')
fi

# Clean up empty brackets/parens from missing values
output=$(echo "$output" | sed 's/\[\]//g; s/()//g; s/  */ /g; s/^ *//; s/ *$//')

echo -en "$output"
STATUSLINE_EOF

    # Insert the actual format into the script
    sed -i '' "s|__FORMAT_PLACEHOLDER__|$format|g" "$script_file"

    chmod +x "$script_file"

    echo -e "${GREEN}✓ Claude Code status line installed${NC}"
    echo ""
    echo "Format: $format"
    echo ""
    echo "Commands:"
    echo "  pwt claude-setup vars      # See all variables"
    echo "  pwt claude-setup format    # Change format"
    echo "  pwt claude-setup preview   # Test output"
    echo ""
    echo "Restart Claude Code or run /statusline to apply."
}
