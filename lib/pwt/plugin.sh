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

# Command: plugin
# Manage pwt plugins
# Usage: pwt plugin [list|install|remove|path|help]
cmd_plugin() {
    local plugins_dir="$PWT_DIR/plugins"
    local action="${1:-list}"

    case "$action" in
        list|ls)
            echo -e "${BLUE}Installed plugins:${NC}"
            echo ""
            if [ -d "$plugins_dir" ] && [ "$(ls -A "$plugins_dir" 2>/dev/null)" ]; then
                for plugin in "$plugins_dir"/pwt-*; do
                    [ -x "$plugin" ] || continue
                    local name=$(basename "$plugin" | sed 's/^pwt-//')
                    local version=""
                    local desc=""

                    # Try to get version/description from plugin --version or first comment
                    if head -5 "$plugin" | grep -q "^# Description:"; then
                        desc=$(head -10 "$plugin" | grep "^# Description:" | sed 's/^# Description: *//')
                    fi
                    if head -5 "$plugin" | grep -q "^# Version:"; then
                        version=$(head -10 "$plugin" | grep "^# Version:" | sed 's/^# Version: *//')
                    fi

                    printf "  ${GREEN}%-15s${NC}" "$name"
                    [ -n "$version" ] && printf " v%s" "$version"
                    [ -n "$desc" ] && printf "  - %s" "$desc"
                    echo ""
                done
            else
                echo "  (no plugins installed)"
                echo ""
                echo "Install plugins:"
                echo "  pwt plugin install <path-or-url>"
                echo "  cp my-plugin ~/.pwt/plugins/pwt-mycommand"
            fi
            echo ""
            echo -e "${DIM}Plugin directory: $plugins_dir${NC}"
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

            mkdir -p "$plugins_dir"

            local plugin_name=""
            local dest=""

            if [[ "$source" == http* ]]; then
                # Download from URL
                plugin_name=$(basename "$source")
                [[ "$plugin_name" != pwt-* ]] && plugin_name="pwt-$plugin_name"
                dest="$plugins_dir/$plugin_name"

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
                dest="$plugins_dir/$plugin_name"

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
            local plugin="$plugins_dir/$name"

            if [ ! -f "$plugin" ]; then
                pwt_error "Error: Plugin not found: ${name#pwt-}"
                exit 1
            fi

            rm "$plugin"
            echo -e "${GREEN}✓${NC} Removed plugin: ${name#pwt-}"
            ;;

        path)
            echo "$plugins_dir"
            ;;

        create)
            local name="${2:-}"
            if [ -z "$name" ]; then
                echo -e "${RED}Usage: pwt plugin create <name>${NC}"
                exit 1
            fi

            mkdir -p "$plugins_dir"
            [[ "$name" != pwt-* ]] && name="pwt-$name"
            local plugin="$plugins_dir/$name"
            local cmd_name="${name#pwt-}"

            if [ -f "$plugin" ]; then
                pwt_error "Error: Plugin already exists: $cmd_name"
                exit 1
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
            echo "  remove <name>     Remove installed plugin"
            echo "  create <name>     Create new plugin from template"
            echo "  path              Print plugins directory"
            echo ""
            echo "Plugin Structure:"
            echo "  Plugins are executable scripts in ~/.pwt/plugins/"
            echo "  Named pwt-<command>, invoked as 'pwt <command>'"
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
