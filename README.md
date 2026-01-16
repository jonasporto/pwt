# pwt - Power Worktrees

A generic tool for managing git worktrees across multiple projects.

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| git | ✅ | Core worktree management |
| jq | ✅ | JSON metadata storage |
| lsof | Recommended | Port conflict detection |
| bun/node | Optional | Pwtfile.js support |
| ruby | Optional | Pwtfile.rb support |

## Quick Start

```bash
# Zero-config: just run from any git project
cd ~/Projects/myapp
pwt create feature-branch master "my feature"
pwt list
pwt remove feature-branch
```

## Commands

| Command | Description |
|---------|-------------|
| `create <branch> [base] [desc]` | Create new worktree |
| `list` | List worktrees and status |
| `info [worktree]` | Show worktree details |
| `remove <worktree>` | Remove worktree |
| `server` | Start development server |
| `fix-port [worktree]` | Resolve port conflict |
| `auto-remove [target]` | Remove merged worktrees |
| `meta [action]` | Manage metadata |
| `project [action]` | Manage project configs |
| `config [key] [value]` | Configure current project |

## Worktree Naming

The `<worktree>` identifier is derived from the `<branch>` input by removing path prefix and sanitizing:

| Branch Input | Worktree Name |
|--------------|---------------|
| `my-feature` | `my-feature` |
| `feature/my-feature` | `my-feature` |
| `jp/TICKET-123-fix-bug` | `TICKET-123-fix-bug` |
| `bugfix/fix_something` | `fix_something` |

## Project Selection

pwt auto-detects the project from your current directory. You can also:

```bash
pwt myproject create ...       # Project as first argument
pwt --project myproject ...    # Explicit flag
```

## Pwtfile

Create a `Pwtfile` in your project root to customize worktree behavior:

```bash
# Pwtfile
PORT_BASE=5001  # First worktree uses 5001, second uses 5002, etc.

setup() {
    echo "Setting up worktree..."
    bundle install
}

teardown() {
    echo "Cleaning up..."
}

server() {
    PORT="$PWT_PORT" bin/dev
}
```

### Available Variables

| Variable | Description |
|----------|-------------|
| `$PWT_PORT` | Allocated port for this worktree |
| `$PWT_WORKTREE` | Worktree name |
| `$PWT_WORKTREE_PATH` | Full path to worktree |
| `$PWT_BRANCH` | Git branch name |
| `$PWT_TICKET` | Same as worktree name (customize via Pwtfile) |
| `$PWT_PROJECT` | Project name |
| `$MAIN_APP` | Path to main app |

### Global Pwtfile

Create `~/.pwt/Pwtfile` for hooks that run on all projects:

```bash
# ~/.pwt/Pwtfile
setup() {
    # Add to zoxide for quick navigation
    zoxide add "$PWT_WORKTREE_PATH"
}
```

## Configuration

### Project Config

```bash
pwt project init myproject
pwt project set myproject main_app ~/Projects/myapp
pwt project set myproject worktrees_dir ~/Projects/myapp-worktrees
pwt project set myproject branch_prefix "jp/"
```

### Directory Structure

```
~/.pwt/
├── meta.json           # Worktree metadata
├── Pwtfile             # Global hooks
└── projects/
    └── myproject/
        └── config.json
```

## Port Allocation

- Ports are automatically allocated starting from `PORT_BASE`
- pwt checks for port conflicts before allocation
- Use `pwt fix-port` to resolve conflicts
- `pwt list` shows port status (free/conflict)

## Tab Completion

### Zsh

Add to your `~/.zshrc`:

```bash
fpath=(~/dotfiles/pwt/completions $fpath)
autoload -Uz compinit && compinit
```

Then restart your terminal or run:

```bash
source ~/.zshrc
```

## Examples

```bash
# Create worktree for a ticket
pwt create TICKET-123 master "implement feature"

# List all worktrees with status
pwt list

# Start server in current worktree
pwt server

# Check worktree info
pwt info TICKET-123

# Remove when done
pwt remove TICKET-123

# Clean up all merged worktrees
pwt auto-remove master
```

