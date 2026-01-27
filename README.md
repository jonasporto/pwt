# pwt - Power Worktrees

[![Tests](https://github.com/jonasporto/pwt/actions/workflows/ci.yml/badge.svg)](https://github.com/jonasporto/pwt/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](CHANGELOG.md)

**Stop opening 6 editors. One stable path. Multiple worktrees.**

![pwt demo](demo.gif)

pwt lets you work with multiple git worktrees using a single editor and a single stable path.

```bash
# Open editor once
subl "$(pwt current)"

# Switch context instantly
pwt use TICKET-456    # symlink swaps, editor sees new code
pwt use TICKET-789    # switch again, no new windows

# See where you are (everywhere)
pwt ps1               # pwt@TICKET-789
```

**The core insight:** You don't need 6 editor windows. You need one editor pointing to a stable path, and the ability to swap what's behind that path.

---

pwt manages git worktrees with port allocation and project isolation. It's framework-agnostic: Rails, Node, Go, Python — pwt doesn't care. Your project-specific setup lives in `Pwtfile`, not in pwt's core.

## TL;DR

- One editor, one stable path, infinite worktrees
- `pwt use` swaps code instantly via symlink
- Worktrees by default, clones when needed (`--clone`)
- Project logic lives in `Pwtfile` (setup/server/teardown)

## Navigation

**Start here:** [Install](#install) · [30-Second Demo](#30-second-demo) · [Quick Start](#quick-start)

**Deep dive:** [Why not clones?](#why-not-just-clones) · [Commands](#commands) · [Pwtfile](#pwtfile) · [Plugins](#plugins) · [Shell Integration](#shell-integration)

**Philosophy:** [Capistrano-style symlink](#capistrano-style-current-symlink) · [rvm-like switching](#philosophy-rvm-like-context-switching)

---

## Why not just clones?

Cloning the same repository multiple times is a valid and common workflow — especially for developers who want full isolation, zero constraints, and fewer surprises.

So why does pwt default to Git worktrees?

### The short answer

Because **Git worktrees share Git objects**, while clones duplicate them.

For large repositories, this can save **hundreds of megabytes or even gigabytes** per workspace.

### What worktrees share (and what they don't)

**Shared across worktrees:**
- Git objects (`.git/objects`)
- Commit history
- Trees and blobs

**Not shared:**
- Working directory files (each worktree has a full copy)
- `.env`, `node_modules`, `vendor`, `tmp`, build artifacts
- Git index and working state

In other words: worktrees share *history*, not *files*.

### Why people still prefer clones (and that's okay)

There are two very real reasons developers avoid worktrees:

**1. Branch locking**

Git does not allow the same branch to be checked out in multiple worktrees:

```
fatal: 'feature-x' is already checked out
```

Clones don't have this limitation.

**2. Submodules**

Submodules rely on internal Git paths that don't always behave well with worktrees. In practice, many teams find that **multiple clones are simply more predictable** when submodules are involved.

### pwt's approach

pwt does **not** force a single workflow. You can choose between:

| Mode | Flag | Pros |
|------|------|------|
| **Worktree (default)** | - | Faster, lower disk usage, shared Git objects |
| **Clone** | `--clone` | Full isolation, no branch locks, safer with submodules |

Both modes use the **same pwt commands**, metadata, hooks, and Pwtfile logic.

```bash
pwt create feature master              # Creates worktree (default)
pwt create feature master --clone      # Creates clone instead
```

> Use worktrees when you can.
> Use clones when you need to.
> pwt handles both.

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| git | ✅ | Core worktree management |
| jq | ✅ | JSON metadata storage |
| lsof | Recommended | Port conflict detection |
| fzf | Recommended | Interactive selection (pwt select) |
| bun/node | Optional | Pwtfile.js support |
| ruby | Optional | Pwtfile.rb support |

## Install

```bash
# Clone and install
git clone https://github.com/jonasporto/pwt.git ~/.pwt-src
cd ~/.pwt-src
make install PREFIX=~/.local

# Add to ~/.zshrc (or ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"
eval "$(pwt shell-init zsh)"

# Verify
pwt --version
pwt doctor
```

**Dependencies:** `jq` (required), `fzf` (optional)
```bash
brew install jq fzf  # macOS
```

See [INSTALL.md](INSTALL.md) for bash/fish setup and troubleshooting.

## 30-Second Demo

```bash
# Initialize your project
cd ~/Projects/myapp
pwt init

# Create a worktree and open it
pwt create TICKET-123 main "fix login bug"
cd "$(pwt current)"

# Switch context instantly
pwt use TICKET-456

# Always know where you are
pwt ps1   # pwt@TICKET-456
```

**The key insight:** `pwt use` swaps a symlink. Your editor stays open, pointing to `$(pwt current)`. When you switch, the editor sees different code — no new windows.

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

> **Note:** Project name is derived from the repo directory (e.g., `myapp`). Use `pwt project list` to see configured projects.

## Commands

| Command | Description |
|---------|-------------|
| `init [url]` | Initialize project (clone from URL or configure current repo) |
| `create <branch> [base] [desc]` | Create new worktree (see flags below) |
| `list [flags]` | List worktrees and status (see flags below) |
| `status [flags]` | Interactive TUI dashboard (like htop) |
| `select [flags]` | Interactive worktree selector with preview (requires fzf) |
| `pick [--dirty]` | Interactive selector + auto-use (sets current symlink) |
| `info [worktree]` | Show worktree details |
| `remove [worktree] [flags]` | Remove worktree (current if no arg) |
| `cd [worktree\|@\|-]` | Navigate to worktree (@ main, - previous, none = last used) |
| `use <worktree>` | Switch current symlink to worktree (Capistrano-style) |
| `current [flags]` | Show current worktree (path on stdout, context on stderr) |
| `ps1` | Fast prompt helper (e.g., `pwt@TICKET-123`) |
| `run [worktree] <cmd>` | Run command in worktree (uses current/main if omitted) |
| `for-each <cmd>` | Run command in all worktrees |
| `editor [worktree]` | Open worktree in configured editor |
| `ai [worktree] [-- args]` | Start AI tool in worktree |
| `open [worktree]` | Open worktree in Finder |
| `diff <wt1> [wt2]` | Show diff between worktrees |
| `copy <src> <dest> <patterns...>` | Copy files between worktrees |
| `server` | Start development server |
| `fix-port [worktree]` | Resolve port conflict |
| `auto-remove [target] [flags]` | Remove merged worktrees |
| `tree [flags]` | Visual tree view of worktrees (`--all`, `--dirty`, `--ports`) |
| `doctor` | Check system health and configuration |
| `shell-init` | Output shell function for cd/select integration |
| `plugin [action]` | Manage plugins (list, install, remove, create) |
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
| `--clone` | Use git clone instead of worktree (avoids branch locks, better for submodules) |
| `--dry-run, -n` | Show what would be created without creating |
| `--` | Everything after is the description (for multi-word) |

### List Flags

| Flag | Description |
|------|-------------|
| `-v, --verbose` | Show detailed output (original format) |
| `--dirty` | Only show worktrees with uncommitted changes |
| `--porcelain` | Output machine-readable JSON |

**Subcommand:** `pwt list statusline` — compact output for shell prompts.

### Select Flags

| Flag | Description |
|------|-------------|
| `--dirty` | Only show worktrees with uncommitted changes |
| `--no-preview` | Disable the preview pane |

**Keybindings in select:**
| Key | Action |
|-----|--------|
| `Enter` | Navigate to selected worktree |
| `Ctrl+E` | Open editor in selected worktree |
| `Ctrl+A` | Start AI tool in selected worktree |
| `Ctrl+O` | Open selected worktree in Finder |
| `Esc` | Cancel selection |

### Remove Flags

| Flag | Description |
|------|-------------|
| `--with-branch` | Also delete the branch (if merged) |
| `--force-branch` | Force delete the branch (even if not merged) |
| `--kill-port` | Kill processes using the worktree's port (opt-in) |
| `-y, --yes` | Skip confirmation prompts |

### Auto-remove Flags

| Flag | Description |
|------|-------------|
| `--dry-run, -n` | Show what would be removed without removing |

### Current Flags

`pwt current` works from **anywhere** (uses symlink, not just pwd).

**Default output (no flags):** path on stdout, context on stderr — pipe-friendly:
```bash
cd "$(pwt current)"      # Only path goes to cd
subl "$(pwt current)"    # Context shows in terminal
```

| Flag | Description |
|------|-------------|
| (default) | Path on stdout, context on stderr |
| `--name` | Output only worktree name |
| `--port` | Output only port number |
| `--branch` | Output only branch name |
| `--path` | Output only worktree path (same as default stdout) |
| `--json` | Output full info as JSON |

## Worktree Naming

The `<worktree>` identifier is derived from the `<branch>` input by removing path prefix and sanitizing:

| Branch Input | Worktree Name |
|--------------|---------------|
| `my-feature` | `my-feature` |
| `feature/my-feature` | `my-feature` |
| `user/TICKET-123-fix-bug` | `TICKET-123-fix-bug` |
| `bugfix/fix_something` | `fix_something` |

## Project Selection

pwt auto-detects the project from your current directory. You can also:

```bash
pwt myproject create ...       # Project as first argument
pwt --project myproject ...    # Explicit flag
```

## Pwtfile

**Pwtfile is a project-local workflow file, similar in spirit to a Makefile, but scoped to worktree lifecycle.**

pwt is not about infrastructure — it's about workflow. The core handles worktree management (create, list, remove) and port allocation. Everything else is delegated to your Pwtfile: dependency installation, database setup, server configuration, cleanup.

Create a `Pwtfile` in your project root:

```bash
# Pwtfile
PORT_BASE=5001  # First worktree uses 5001, second uses 5002, etc.

setup() {
    echo "Setting up worktree..."
    # Install dependencies, create databases, copy configs...
    # This is YOUR project's setup logic
}

teardown() {
    echo "Cleaning up..."
    # Drop databases, remove temp files...
}

server() {
    # Start YOUR server however you want
    # $PWT_PORT is available for port configuration
    npm run dev -- --port "$PWT_PORT"
}
```

**Example: Rails + Vite project**
```bash
# Pwtfile for Rails
setup() {
    pwtfile_copy ".env"
    bundle install
    yarn install
    # Additional ports: VITE_PORT=$((PWT_PORT+1))
}

server() {
    foreman start -p "$PWT_PORT"
}
```

**Example: Node.js project**
```bash
# Pwtfile for Node
setup() {
    npm install
}

server() {
    PORT="$PWT_PORT" npm start
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
| `pwtfile_replace_literal <file> <from> <to>` | Safe literal string replacement (no regex) |
| `pwtfile_replace_re <file> <pattern> <replacement>` | Regex replacement via perl (cross-platform) |
| `pwtfile_hash_port [name] [base]` | Deterministic port from worktree name |

Short aliases are available inside Pwtfile: `replace_literal`, `replace_re`.

```bash
# Pwtfile
setup() {
    pwtfile_copy ".env"              # Copy .env from main
    pwtfile_symlink "node_modules"   # Share node_modules (save disk space)
    pwtfile_symlink ".cache"         # Share cache

    # Safe replacements (handles special chars like ERB, $, etc.)
    replace_literal "config/database.yml" "db_test" "db_test_wt${PWT_PORT}"
    replace_re ".env" "PORT=\d+" "PORT=$PWT_PORT"
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
pwt config branch_prefix "user/"
pwt config worktrees_dir ~/Projects/myapp-worktrees
```

Config is stored in `~/.pwt/projects/<name>/config.json`:

```json
{
  "path": "/Users/you/Projects/myapp",
  "remote": "git@github.com:user/myapp.git",
  "worktrees_dir": "/Users/you/Projects/myapp-worktrees",
  "branch_prefix": "user/",
  "aliases": ["app", "myapp"]
}
```

### Directory Structure

```
~/.pwt/
├── meta.json           # Worktree metadata
├── Pwtfile             # Global hooks
├── plugins/            # Custom plugins
└── projects/
    └── myproject/
        └── config.json
```

## Plugins

pwt supports plugins for extending functionality. Plugins are executable scripts in `~/.pwt/plugins/` that pwt automatically discovers and runs.

### Using Plugins

```bash
# List installed plugins
pwt plugin list

# Install a plugin from file
pwt plugin install /path/to/my-plugin.sh

# Create a new plugin from template
pwt plugin create my-feature

# Remove a plugin
pwt plugin remove my-feature

# Show plugins directory
pwt plugin path
```

### Official Plugins

pwt ships with two optional plugins in the `plugins/` directory:

**pwt-aitools** — AI integration:
```bash
cp plugins/pwt-aitools ~/.pwt/plugins/
pwt aitools topology              # LLM-powered analysis of Pwtfile
pwt aitools context               # Generate markdown context for AI
```

**pwt-extras** — Extra utilities:
```bash
cp plugins/pwt-extras ~/.pwt/plugins/
pwt extras benchmark              # Compare worktree vs clone disk usage
pwt extras marker TICKET-123 🚧   # Set worktree markers
pwt extras conflicts              # Show file overlap between worktrees
pwt extras prompt zsh             # Output prompt integration snippets
```

### Creating Custom Plugins

Create a plugin with `pwt plugin create`:

```bash
pwt plugin create deploy
# Creates ~/.pwt/plugins/pwt-deploy
```

Or create manually. Plugin requirements:
1. Named `pwt-<name>` (e.g., `pwt-deploy`)
2. Located in `~/.pwt/plugins/`
3. Executable (`chmod +x`)

Example plugin:

```bash
#!/bin/bash
# ~/.pwt/plugins/pwt-deploy
# Description: Deploy worktree to staging

case "${1:-}" in
    staging)
        echo "Deploying $PWT_WORKTREE to staging..."
        # your deploy logic
        ;;
    production)
        echo "Deploying $PWT_WORKTREE to production..."
        ;;
    *)
        echo "Usage: pwt deploy [staging|production]"
        ;;
esac
```

### Plugin Environment Variables

Plugins receive context from pwt:

| Variable | Description |
|----------|-------------|
| `$PWT_DIR` | pwt config directory (~/.pwt) |
| `$PWT_VERSION` | pwt version |
| `$PWT_PROJECT` | Current project name (if in project) |
| `$PWT_MAIN_APP` | Main app directory |
| `$PWT_WORKTREES_DIR` | Worktrees directory |
| `$PWT_WORKTREE` | Current worktree name (if in worktree) |

### Plugin vs Pwtfile

| Feature | Pwtfile | Plugin |
|---------|---------|--------|
| Scope | Per-project | Global |
| Location | Project root | ~/.pwt/plugins/ |
| Use case | Project-specific setup/server/teardown | Reusable commands across all projects |
| Example | Rails setup, npm install | Custom deploy, CI integration |

## Port Allocation

- Ports are automatically allocated starting from `PORT_BASE`
- pwt checks for port conflicts before allocation
- Use `pwt fix-port` to resolve conflicts
- `pwt list` shows port status (free/conflict)

## Shell Integration

Enable `pwt cd` navigation and tab completion:

**Zsh (~/.zshrc):**
```bash
eval "$(pwt shell-init zsh)"
autoload -Uz compinit && compinit
```

**Bash (~/.bashrc):**
```bash
eval "$(pwt shell-init bash)"
```

**Fish (~/.config/fish/config.fish):**
```fish
pwt shell-init fish | source
```

Then restart your terminal or source your config file.

### Navigation

```bash
pwt cd TICKET-123   # Go to worktree
pwt cd              # Go to last-used worktree (or main if none)
pwt cd @            # Go to main worktree (explicit)
pwt cd -            # Go to previous worktree (like cd -)
```

pwt remembers your last-used worktree per project. When you `pwt cd` without arguments, it returns you to where you were working.

The `-` shortcut works across projects:

```bash
pwt project-a cd TICKET-123    # Go to project-a worktree
pwt project-b cd TASK-1        # Go to project-b worktree
pwt cd -                       # Back to project-a/TICKET-123
pwt cd -                       # Back to project-b/TASK-1
```

### Environment Variables

When navigating via `pwt cd`, these environment variables are set:

| Variable | Description |
|----------|-------------|
| `$PWT_WORKTREE` | Current worktree name (unset when in main app) |
| `$PWT_PREVIOUS_PATH` | Previous directory path (enables `pwt cd -`) |

Useful for:
- Custom shell prompts
- Scripts that need to know the current worktree
- Integration with other tools

### Prompt Integration

**Quick setup (zsh):**
```bash
# Add to ~/.zshrc
pwt_prompt_info() {
  [[ -n "$PWT_WORKTREE" ]] && echo "[wt:$PWT_WORKTREE] "
}
PROMPT='$(pwt_prompt_info)'$PROMPT
```

**With port (useful for debugging):**
```bash
pwt_prompt_info() {
  if [[ -n "$PWT_WORKTREE" ]]; then
    local port=$(pwt current --port 2>/dev/null)
    echo "[wt:$PWT_WORKTREE:$port] "
  fi
}
```

### Current Worktree Info

Use `pwt current` to query the active worktree:

```bash
pwt current           # Path on stdout, context on stderr
pwt current --name    # Just the name (for scripts)
pwt current --port    # Just the port
pwt current --json    # Full JSON (for tooling)
```

This is useful for shell scripts, CI, or custom tooling that needs to know the current context.

## Capistrano-style Current Symlink

**"Think Capistrano's `current`, but for local worktrees."**

pwt maintains a symlink pointing to your active worktree:
```
~/.pwt/projects/myapp/current -> /path/to/worktrees/TICKET-123
```

### `pwt use` — Switch Context

```bash
pwt use TICKET-456
# current → TICKET-456 (branch jp/TICKET-456)
#          port :5009
```

This atomically swaps the symlink. It does **NOT**:
- Open a new editor window
- Kill any processes
- Change your shell directory

### Single Editor Workspace

Open your editor **once**, always pointing to `current`:

```bash
subl "$(pwt current)"   # or just remember the path

# Later, switch context:
pwt use TICKET-789

# Editor now sees different code (symlink resolved)
```

Works with: Sublime, VS Code, Cursor, Neovim, JetBrains (may need "Reload Project").

### `pwt ps1` — Fast Prompt Helper

`pwt ps1` prints the active workspace label for shell prompts and status bars.

**Fast:** No git, no directory scanning — just reads a symlink.

```bash
$ pwt ps1
pwt@TICKET-123

# If pwd is in a DIFFERENT worktree than current:
pwt@TICKET-123!    # The ! warns of mismatch
```

**Shell integration (add to ~/.zshrc):**
```bash
pwt_ps1() {
  pwt ps1 2>/dev/null
}
PS1='$(pwt_ps1) '$PS1
```

**Result:** `pwt@TICKET-123 jonas@mbp ~/code $`

**tmux:**
```bash
set -g status-right '#(pwt ps1)'
```

**Neovim:**
```vim
:set statusline+=%{system('pwt\ ps1')}
```

> **ps1 vs statusline:** Use `pwt ps1` for current context (fast, symlink-based). Use `pwt list statusline` for a global overview of all worktrees (useful for dashboards/tmux).

### Edge Cases & Limitations

**What pwt handles:**
- Deleting current worktree → clears symlink automatically
- Broken symlink → `pwt current` shows helpful error
- Creating worktree → auto-sets as current

**What you should know:**
| Situation | What happens |
|-----------|--------------|
| Untracked files | Stay in the worktree directory (not copied) |
| Editor buffers after `use` | May show stale content — reload or close tabs |
| Running servers in `current` path | **Not recommended** — servers pin paths |
| File watchers (LSP, TypeScript) | May need manual reload after `use` |

**pwt does NOT try to:**
- Manage running servers or processes
- Sandbox file changes
- Auto-reload editors
- Guarantee watcher consistency

The symlink is a **convenience for editing**, not a safety mechanism.

### Do / Don't

| ✅ Do | ⚠️ Don't |
|-------|----------|
| Open editor via `$(pwt current)` | Run servers from `current` path |
| Use `pwt use` to switch context | Expect LSP to auto-reload on switch |
| Run `pwt server` from worktree directory | Assume watchers follow symlinks |
| Use `pwt ps1` for prompt context | Store state in `current` path |

## Philosophy: rvm-like Context Switching

pwt gives you **95% of the rvm experience** without the dangerous hacks.

**What rvm does (and why it's risky):**
- Modifies `$PATH` dynamically
- Symlink swaps between versions
- Magic directory detection with hooks

**What pwt does instead:**
- **Real directories** — each worktree is a full working copy
- **Smart switcher** — `pwt select` with fzf, preview, keybindings
- **Hidden paths** — worktrees live in `project-worktrees/`, out of your way
- **Visible context** — `$PWT_WORKTREE`, statusline, prompt integration
- **Session-aware commands** — `pwt server`, `pwt editor` know where you are
- **Last-used memory** — `pwt cd` returns to your previous context

The result: switch between tickets as easily as `rvm use ruby-3.2`, but without touching your shell's internals.

```bash
# rvm-style workflow with pwt
pwt select              # Pick a worktree interactively
pwt cd                  # Return to last-used worktree
pwt current --name      # Which worktree am I in?
pwt server              # Start server for current context
```

## Visual Commands

### `pwt status` — Interactive Dashboard

Full-screen TUI dashboard (like htop) for monitoring worktrees:

```bash
pwt status         # Current project
pwt status --all   # All projects
```

**Features:**
- Real-time git status, server status, port usage
- Navigate with arrow keys, Tab between panes
- Quick actions: start server, open editor, git operations
- Customizable themes via `PWT_THEME` environment variable

**Keyboard shortcuts:**
| Key | Action |
|-----|--------|
| `↑↓` / `jk` | Navigate |
| `Tab` | Switch pane |
| `Enter` | Select/drill down |
| `s` | Toggle server |
| `e` | Open editor |
| `q` / `Esc` | Quit |

### `pwt tree` — Factual Structure

See your worktrees at a glance:

```
$ pwt tree
myapp
├─ @ (main)                    master
├─ TICKET-123        :5001     feature/login    *
├─ TICKET-456        :5002     fix/api-error
└─ TICKET-789        :5003     refactor/auth    +
```

Flags: `--all` (all projects), `--dirty` (uncommitted only), `--ports` (show ports)

## Examples

```bash
# Initialize new project from URL
pwt init git@github.com:company/project.git

# Initialize existing repo
cd ~/Projects/existing-project
pwt init

# Create worktree for a ticket
pwt create TICKET-123 master "implement feature"
pwt create TICKET-123 master implement feature   # quotes optional

# Create and open in editor + AI
pwt create TICKET-123 master "feature" -e -a

# Create from a tag (hotfix)
pwt create hotfix --from v1.2.3
pwt create hotfix --from v1.2.3 -- fix critical bug

# Create variant from current branch
pwt create variant --from-current

# Preview what would be created
pwt create TICKET-123 master --dry-run

# Create clone instead of worktree (for repos with submodules)
pwt create TICKET-123 master --clone
pwt create TICKET-123 master "feature" --clone -e -a

# Navigate to worktree (requires shell-init)
pwt cd TICKET-123
pwt cd -              # Go back to previous location

# List all worktrees with status
pwt list

# List only dirty worktrees
pwt list --dirty

# Get JSON output for scripting
pwt list --porcelain | jq '.worktrees[].name'

# Run command in worktree without cd'ing
pwt run TICKET-123 npm test    # in specific worktree
pwt run @ git status           # in main app
pwt run npm test               # in current worktree or main

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

# Remove current worktree (when inside one)
pwt remove

# Remove worktree + delete branch (if merged)
pwt remove TICKET-123 --with-branch

# Force remove worktree + delete branch
pwt remove TICKET-123 --force-branch

# Interactive worktree selection (fzf)
pwt select                  # with preview (default)
pwt select --dirty          # only dirty worktrees
pwt select --no-preview     # without preview pane
# Keybindings: Ctrl+E (editor), Ctrl+A (ai), Ctrl+O (open)

# Run command in all worktrees
pwt for-each git status -s
pwt for-each npm test

# Get statusline for shell prompts
pwt list statusline          # outputs: [TICKET-123 +! ↑3]

# Query current worktree
pwt current                  # path on stdout, context on stderr
pwt current --name           # just name (for scripts)
pwt current --port           # just port
pwt current --json           # full JSON
cd "$(pwt current)"          # pipe-friendly (only path goes to cd)

# Switch current symlink (Capistrano-style)
pwt use TICKET-456           # swap symlink, no editor/process changes
pwt use 123                  # fuzzy match: TICKET-123
pwt pick                     # interactive selector + auto-use
pwt pick --dirty             # only dirty worktrees

# Fast prompt helper
pwt ps1                      # outputs: pwt@TICKET-123
pwt ps1                      # outputs: pwt@TICKET-123! (if pwd differs)

# Use project alias
pwt myapp list
pwt myapp create feature master "new feature"
```

## Known Limitations

### Editor Git Status with `current` Symlink

When using the `current` symlink (`~/.pwt/projects/<project>/current`), editors like Sublime Text cache git repository information when the folder is opened.

**What works:** File contents update correctly when you `pwt use` another worktree - the symlink points to new content and editors see the changes.

**What doesn't work:** Git status in the editor's status bar stays stale. It shows the branch from when you first opened the folder, not the current worktree's branch.

**Why:** Editors detect the `.git` directory once at open time. When the symlink target changes to a different worktree (different `.git`), editors don't re-detect the repository.

**Workarounds:**
- Close and reopen the folder in editor
- Use `subl "$(pwt current)"` after switching (opens fresh)
- Accept that file content is correct, status bar is stale

**This affects:** Sublime Text, VS Code, and most editors. It's not a pwt bug - it's how editors handle symlinks to git repositories.

## Documentation

- **Man page:** `man pwt` (full command reference)
- **FAQ:** [FAQ.md](FAQ.md) - common questions
- **Changelog:** [CHANGELOG.md](CHANGELOG.md) - version history
- **Install guide:** [INSTALL.md](INSTALL.md) - detailed setup

## Contributing

```bash
# Run tests
make test

# Check syntax
make lint

# Install locally for development
make install PREFIX=~/.local
```

## FAQ

See [FAQ.md](FAQ.md) for common questions about:
- Handling dependencies across worktrees
- Sharing ports with teammates
- Running commands in all worktrees
- Cleaning up old worktrees
- Quick navigation tips
