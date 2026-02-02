#!/bin/bash
# ============================================================
# pwt plugin module
# Plugin management system
# ============================================================
#
# This module is sourced by bin/pwt when the plugin command is used.
#
# Dependencies:
#   - Requires variables from bin/pwt: PWT_DIR, RED, GREEN, BLUE, NC
#

# Guard against multiple sourcing
[[ -n "${_PWT_PLUGIN_LOADED:-}" ]] && return 0
_PWT_PLUGIN_LOADED=1

# Get all plugin directories (user first, then system)
# User plugins override system plugins with the same name
_get_plugin_dirs() {
    local dirs=()

    # 1. User plugins (highest priority, always writable)
    dirs+=("$PWT_DIR/plugins")

    # 2. Check all possible system plugin locations
    # This is more robust than trying to detect installation method

    # Homebrew (check if installed)
    if command -v brew &>/dev/null; then
        local brew_prefix
        brew_prefix="$(brew --prefix 2>/dev/null)"
        [ -d "$brew_prefix/share/pwt/plugins" ] && dirs+=("$brew_prefix/share/pwt/plugins")
    fi

    # Standard Homebrew locations (in case brew command not in PATH)
    [ -d "/opt/homebrew/share/pwt/plugins" ] && dirs+=("/opt/homebrew/share/pwt/plugins")
    [ -d "/usr/local/share/pwt/plugins" ] && dirs+=("/usr/local/share/pwt/plugins")

    # ~/.local (common PREFIX for source/curl installs)
    [ -d "$HOME/.local/share/pwt/plugins" ] && dirs+=("$HOME/.local/share/pwt/plugins")

    # npm global (typical locations)
    local npm_prefix
    if npm_prefix="$(npm config get prefix 2>/dev/null)" && [ -d "$npm_prefix/share/pwt/plugins" ]; then
        dirs+=("$npm_prefix/share/pwt/plugins")
    fi

    # Print unique directories
    printf '%s\n' "${dirs[@]}" | awk '!seen[$0]++'
}

# Find a plugin by name (searches all directories, user first)
_find_plugin() {
    local name="$1"
    [[ "$name" != pwt-* ]] && name="pwt-$name"

    local dir
    while IFS= read -r dir; do
        local plugin="$dir/$name"
        if [ -x "$plugin" ]; then
            echo "$plugin"
            return 0
        fi
    done < <(_get_plugin_dirs)

    return 1
}

# Command: plugin
# Manage pwt plugins
# Usage: pwt plugin [list|install|remove|path|help]
cmd_plugin() {
    local user_plugins_dir="$PWT_DIR/plugins"
    local action="${1:-list}"

    case "$action" in
        list|ls)
            echo -e "${BLUE}Installed plugins:${NC}"
            echo ""
            local found_any=false
            local seen_plugins=""

            # List plugins from all directories (user first for override display)
            local dir
            while IFS= read -r dir; do
                [ -d "$dir" ] || continue

                local dir_has_plugins=false
                for plugin in "$dir"/pwt-*; do
                    [ -x "$plugin" ] || continue

                    local name
                    name=$(basename "$plugin" | sed 's/^pwt-//')

                    # Skip if already seen (user plugins override system)
                    [[ " $seen_plugins " =~ " $name " ]] && continue
                    seen_plugins+=" $name "

                    dir_has_plugins=true
                    found_any=true

                    local version=""
                    local desc=""
                    local source_hint=""

                    # Determine source (check symlinks too)
                    local real_path="$plugin"
                    if [ -L "$plugin" ]; then
                        real_path="$(readlink "$plugin")"
                    fi

                    if [[ "$real_path" == *"/homebrew/"* ]] || [[ "$real_path" == *"/Cellar/"* ]]; then
                        source_hint="${DIM}(brew)${NC}"
                    elif [[ "$real_path" == *"/node_modules/"* ]]; then
                        source_hint="${DIM}(npm)${NC}"
                    elif [[ "$dir" != "$user_plugins_dir" ]]; then
                        source_hint="${DIM}(system)${NC}"
                    fi

                    # Try to get version/description from plugin header
                    if head -5 "$plugin" | grep -q "^# Description:"; then
                        desc=$(head -10 "$plugin" | grep "^# Description:" | sed 's/^# Description: *//')
                    fi
                    if head -5 "$plugin" | grep -q "^# Version:"; then
                        version=$(head -10 "$plugin" | grep "^# Version:" | sed 's/^# Version: *//')
                    fi

                    printf "  ${GREEN}%-15s${NC}" "$name"
                    [ -n "$version" ] && printf " v%s" "$version"
                    [ -n "$source_hint" ] && printf " %b" "$source_hint"
                    [ -n "$desc" ] && printf "  - %s" "$desc"
                    echo ""
                done
            done < <(_get_plugin_dirs)

            if [ "$found_any" = false ]; then
                echo "  (no plugins installed)"
                echo ""
                echo "Install plugins:"
                echo "  pwt plugin install <path-or-url>"
                echo "  cp my-plugin ~/.pwt/plugins/pwt-mycommand"
            fi
            echo ""
            echo -e "${DIM}User plugins: $user_plugins_dir${NC}"
            ;;

        install)
            local source="${2:-}"
            if [ -z "$source" ]; then
                echo -e "${RED}Usage: pwt plugin install <path-or-url>${NC}"
                echo ""
                echo "Examples:"
                echo "  pwt plugin install ./my-plugin.sh"
                echo "  pwt plugin install ~/scripts/pwt-docker"
                echo "  pwt plugin install https://example.com/pwt-github"
                exit 1
            fi

            mkdir -p "$user_plugins_dir"

            local plugin_name=""
            local dest=""

            if [[ "$source" == http* ]]; then
                # Download from URL
                plugin_name=$(basename "$source")
                [[ "$plugin_name" != pwt-* ]] && plugin_name="pwt-$plugin_name"
                dest="$user_plugins_dir/$plugin_name"

                echo -e "${BLUE}Downloading plugin...${NC}"
                if command -v curl &>/dev/null; then
                    curl -fsSL "$source" -o "$dest"
                elif command -v wget &>/dev/null; then
                    wget -q "$source" -O "$dest"
                else
                    pwt_error "Error: curl or wget required for URL install"
                    exit 1
                fi
            else
                # Copy local file
                if [ ! -f "$source" ]; then
                    pwt_error "Error: File not found: $source"
                    exit 1
                fi

                plugin_name=$(basename "$source")
                [[ "$plugin_name" != pwt-* ]] && plugin_name="pwt-$plugin_name"
                dest="$user_plugins_dir/$plugin_name"

                cp "$source" "$dest"
            fi

            chmod +x "$dest"
            local cmd_name=$(echo "$plugin_name" | sed 's/^pwt-//')
            echo -e "${GREEN}✓${NC} Installed plugin: $cmd_name"
            echo "  Run: pwt $cmd_name"
            ;;

        remove|uninstall|rm)
            local name="${2:-}"
            if [ -z "$name" ]; then
                echo -e "${RED}Usage: pwt plugin remove <name>${NC}"
                exit 1
            fi

            # Normalize name
            [[ "$name" != pwt-* ]] && name="pwt-$name"

            # Find the plugin
            local plugin
            plugin=$(_find_plugin "${name#pwt-}") || true

            if [ -z "$plugin" ]; then
                pwt_error "Error: Plugin not found: ${name#pwt-}"
                exit 1
            fi

            # Check if it's a user plugin (can be removed)
            if [[ "$plugin" != "$user_plugins_dir/"* ]]; then
                echo -e "${YELLOW}Warning:${NC} This is a system plugin: $plugin"
                echo "System plugins cannot be removed directly."
                echo ""
                echo "To override it, create your own version:"
                echo "  pwt plugin create ${name#pwt-}"
                exit 1
            fi

            rm "$plugin"
            echo -e "${GREEN}✓${NC} Removed plugin: ${name#pwt-}"
            ;;

        path)
            # Show all plugin directories
            echo -e "${BLUE}Plugin directories:${NC}"
            local dir
            while IFS= read -r dir; do
                if [ -d "$dir" ]; then
                    echo "  $dir"
                else
                    echo "  $dir ${DIM}(not created)${NC}"
                fi
            done < <(_get_plugin_dirs)
            echo ""
            echo -e "${DIM}User plugins go in: $user_plugins_dir${NC}"
            ;;

        create)
            local name="${2:-}"
            if [ -z "$name" ]; then
                echo -e "${RED}Usage: pwt plugin create <name>${NC}"
                exit 1
            fi

            mkdir -p "$user_plugins_dir"
            [[ "$name" != pwt-* ]] && name="pwt-$name"
            local plugin="$user_plugins_dir/$name"
            local cmd_name="${name#pwt-}"

            if [ -f "$plugin" ]; then
                pwt_error "Error: Plugin already exists: $cmd_name"
                exit 1
            fi

            # Check if a system plugin with same name exists
            local existing
            existing=$(_find_plugin "$cmd_name" 2>/dev/null) || true
            if [ -n "$existing" ]; then
                echo -e "${YELLOW}Note:${NC} A system plugin '$cmd_name' exists at:"
                echo "  $existing"
                echo "Your user plugin will override it."
                echo ""
            fi

            cat > "$plugin" << 'TEMPLATE'
#!/bin/bash
# pwt plugin: PLUGIN_NAME
# Description: A custom pwt plugin
# Version: 1.0.0
#
# Available environment variables:
#   PWT_DIR            - pwt directory (~/.pwt)
#   PWT_PROJECT        - Current project name
#   PWT_MAIN_APP       - Main app directory
#   PWT_WORKTREES_DIR  - Worktrees directory
#   PWT_WORKTREE       - Current worktree name (if in one)
#   PWT_WORKTREE_PATH  - Current worktree path
#   PWT_PORT           - Current worktree port
#   PWT_BRANCH         - Current worktree branch
#   PWT_DEFAULT_BRANCH - Default branch (master/main)

set -euo pipefail

case "${1:-}" in
    -h|--help|help)
        echo "Usage: pwt PLUGIN_NAME [subcommand]"
        echo ""
        echo "A custom pwt plugin."
        echo ""
        echo "Subcommands:"
        echo "  help    Show this help"
        echo ""
        echo "Environment:"
        echo "  Project: ${PWT_PROJECT:-<none>}"
        echo "  Worktree: ${PWT_WORKTREE:-<none>}"
        ;;
    *)
        echo "Hello from PLUGIN_NAME plugin!"
        echo ""
        echo "Project: ${PWT_PROJECT:-<not detected>}"
        echo "Worktree: ${PWT_WORKTREE:-<not in worktree>}"
        ;;
esac
TEMPLATE

            # Replace PLUGIN_NAME placeholder
            sed -i.bak "s/PLUGIN_NAME/$cmd_name/g" "$plugin" && rm -f "$plugin.bak"
            chmod +x "$plugin"

            echo -e "${GREEN}✓${NC} Created plugin: $cmd_name"
            echo "  Path: $plugin"
            echo "  Edit: \$EDITOR $plugin"
            echo "  Run:  pwt $cmd_name"
            ;;

        help|-h|--help)
            echo "Usage: pwt plugin <action>"
            echo ""
            echo "Manage pwt plugins - extend pwt with custom commands."
            echo ""
            echo "Actions:"
            echo "  list              List installed plugins"
            echo "  install <source>  Install plugin from file or URL"
            echo "  remove <name>     Remove user plugin"
            echo "  create <name>     Create new plugin from template"
            echo "  path              Show plugin directories"
            echo ""
            echo "Plugin Locations:"
            echo "  User plugins:   ~/.pwt/plugins/         (writable, highest priority)"
            echo "  Homebrew:       \$(brew --prefix)/share/pwt/plugins/"
            echo "  npm:            <prefix>/share/pwt/plugins/"
            echo ""
            echo "User plugins override system plugins with the same name."
            echo ""
            echo "Plugin Structure:"
            echo "  Plugins are executable scripts named pwt-<command>"
            echo "  Invoked as 'pwt <command>'"
            echo ""
            echo "Environment Variables (available to plugins):"
            echo "  PWT_PROJECT        Current project name"
            echo "  PWT_MAIN_APP       Main app directory"
            echo "  PWT_WORKTREES_DIR  Worktrees directory"
            echo "  PWT_WORKTREE       Current worktree name"
            echo "  PWT_PORT           Current worktree port"
            echo "  PWT_BRANCH         Current worktree branch"
            echo ""
            echo "Examples:"
            echo "  pwt plugin list"
            echo "  pwt plugin create github"
            echo "  pwt plugin install ./my-plugin.sh"
            echo "  pwt plugin remove github"
            ;;

        *)
            echo -e "${RED}Unknown action: $action${NC}"
            echo "Run 'pwt plugin help' for usage"
            exit 1
            ;;
    esac
}
