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
# Option 1: Clone and configure in one step
pwt init git@github.com:user/myapp.git
pwt myapp create feature-branch master "my feature"

# Option 2: Configure existing repo
cd ~/Projects/myapp
pwt init
pwt create feature-branch master "my feature"

# Basic workflow
pwt list
pwt server
pwt remove feature-branch
```

## Commands

| Command | Description |
|---------|-------------|
| `init [url]` | Initialize project (clone from URL or configure current repo) |
| `create <branch> [base] [desc]` | Create new worktree (see flags below) |
| `list [flags]` | List worktrees and status |
| `info [worktree]` | Show worktree details |
| `remove <worktree> [flags]` | Remove worktree (see flags below) |
| `cd [worktree\|@]` | Navigate to worktree (requires shell-init) |
| `run <worktree> <cmd>` | Run command in worktree without cd'ing |
| `editor [worktree]` | Open worktree in configured editor |
| `ai [worktree] [-- args]` | Start AI tool in worktree |
| `open [worktree]` | Open worktree in Finder |
| `diff <wt1> [wt2]` | Show diff between worktrees |
| `copy <src> <dest> <patterns>` | Copy files between worktrees |
| `server` | Start development server |
| `fix-port [worktree]` | Resolve port conflict |
| `auto-remove [target] [flags]` | Remove merged worktrees |
| `doctor` | Check system health and configuration |
| `shell-init` | Output shell function for cd integration |
| `meta [action]` | Manage metadata |
| `project [action]` | Manage project configs |
| `config [key] [value]` | Configure current project |

### Create Flags

| Flag | Description |
|------|-------------|
| `-e, --editor` | Open editor after creating |
| `-a, --ai` | Start AI tool after creating |
| `--from <ref>` | Create from specific ref (tag, commit, branch) |
| `--from-current` | Create from current branch |
| `--dry-run, -n` | Show what would be created without creating |

### List Flags

| Flag | Description |
|------|-------------|
| `--dirty` | Only show worktrees with uncommitted changes |
| `--porcelain` | Output machine-readable JSON |

### Remove Flags

| Flag | Description |
|------|-------------|
| `--with-branch` | Also delete the branch (if merged) |
| `--force-branch` | Force delete the branch (even if not merged) |

### Auto-remove Flags

| Flag | Description |
|------|-------------|
| `--dry-run, -n` | Show what would be removed without removing |

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

### Pwtfile Helpers

| Helper | Description |
|--------|-------------|
| `pwtfile_symlink <path>` | Symlink from main app (share node_modules, .cache) |
| `pwtfile_copy <path>` | Copy from main app (.env, config files) |
| `pwtfile_env <var> <value>` | Set environment variable |
| `pwtfile_run <cmd>` | Run command (silent on error) |

```bash
# Pwtfile
setup() {
    pwtfile_copy ".env"              # Copy .env from main
    pwtfile_symlink "node_modules"   # Share node_modules (save disk space)
    pwtfile_symlink ".cache"         # Share cache
}
```

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
# Initialize from URL (clone + configure)
pwt init git@github.com:user/myapp.git

# Or initialize existing repo
cd ~/Projects/myapp
pwt init

# Customize config
pwt config branch_prefix "jp/"
pwt config worktrees_dir ~/Projects/myapp-worktrees
```

Config is stored in `~/.pwt/projects/<name>/config.json`:

```json
{
  "path": "/Users/you/Projects/myapp",
  "remote": "git@github.com:user/myapp.git",
  "worktrees_dir": "/Users/you/Projects/myapp-worktrees",
  "branch_prefix": "jp/",
  "aliases": ["app", "myapp"]
}
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

## Shell Integration

Enable `pwt cd` navigation by adding to your `~/.zshrc`:

```bash
# pwt shell integration (enables pwt cd)
eval "$(pwt shell-init)"

# Tab completion
fpath=(~/dotfiles/pwt/completions $fpath)
autoload -Uz compinit && compinit
```

Then restart your terminal or run `source ~/.zshrc`.

### Navigation

```bash
pwt cd TICKET-123   # Go to worktree
pwt cd              # Go to main worktree
pwt cd @            # Same as above (explicit)
```

### Environment Variable

When navigating via `pwt cd`, the `$PWT_WORKTREE` environment variable is set to the worktree name. Useful for:
- Custom shell prompts
- Scripts that need to know the current worktree
- Integration with other tools

```bash
# Example prompt integration (in ~/.zshrc)
if [[ -n "$PWT_WORKTREE" ]]; then
  PROMPT="[$PWT_WORKTREE] $PROMPT"
fi
```

## Examples

```bash
# Initialize new project from URL
pwt init git@github.com:company/project.git

# Initialize existing repo
cd ~/Projects/existing-project
pwt init

# Create worktree for a ticket
pwt create TICKET-123 master "implement feature"

# Create and open in editor + AI
pwt create TICKET-123 master "feature" -e -a

# Create from a tag (hotfix)
pwt create hotfix --from v1.2.3

# Create variant from current branch
pwt create variant --from-current

# Preview what would be created
pwt create TICKET-123 master --dry-run

# Navigate to worktree (requires shell-init)
pwt cd TICKET-123

# List all worktrees with status
pwt list

# List only dirty worktrees
pwt list --dirty

# Get JSON output for scripting
pwt list --porcelain | jq '.worktrees[].name'

# Run command in worktree without cd'ing
pwt run TICKET-123 npm test
pwt run @ git status

# Open worktree in editor
pwt editor TICKET-123

# Start AI tool in worktree
pwt ai TICKET-123

# Open in Finder
pwt open TICKET-123

# Compare worktree to main
pwt diff TICKET-123

# Compare two worktrees
pwt diff TICKET-123 TICKET-456

# Copy files between worktrees
pwt copy @ TICKET-123 ".env*"

# Check system health
pwt doctor

# Start server in current worktree
pwt server

# Preview merged worktree cleanup
pwt auto-remove master --dry-run

# Clean up all merged worktrees
pwt auto-remove master

# Remove worktree only
pwt remove TICKET-123

# Remove worktree + delete branch (if merged)
pwt remove TICKET-123 --with-branch

# Force remove worktree + delete branch
pwt remove TICKET-123 --force-branch

# Use project alias
pwt myapp list
pwt myapp create feature master "new feature"
```

