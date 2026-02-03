# pwt - Power Worktrees

**A powerful Git worktree workflow for today's multi-project development.**

[![Tests](https://github.com/jonasporto/pwt/actions/workflows/test.yml/badge.svg)](https://github.com/jonasporto/pwt/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.1-green.svg)](CHANGELOG.md)

## Quick demo

![pwt demo](demo.gif)

[Watch in higher quality (mp4)](demo.mp4)

---

✅ Work in parallel
— multiple projects, or parallel changes within the same project

✅ One stable workflow
— keep one editor open, swap branches underneath it

✅ No local conflicts
— automatic per-worktree ports, predictable dev servers

✅ Project-aware automation
— run setup, servers, and custom commands via Pwtfile

✅ Built on Git worktrees
— clones when isolation is required

---

## Install

### Homebrew

```bash
brew install jonasporto/pwt/pwt
```

or:

```bash
brew tap jonasporto/pwt
```

```bash
brew install pwt
```

### npm

```bash
npm i -g @jonasporto/pwt
```

### npx (without installing)

```bash
npx @jonasporto/pwt --help
```

### bun

```bash
bun add -g @jonasporto/pwt
```

### bunx (without installing)

```bash
bunx @jonasporto/pwt --help
```

### curl

```bash
curl -fsSL https://raw.githubusercontent.com/jonasporto/pwt/main/install.sh | bash
```

**Dependencies:** `git`, `jq` (required). `fzf`, `lsof` (optional but highly recommended).

See [INSTALL.md](INSTALL.md) for shell setup and troubleshooting.

---

## Quick Start

```bash
cd ~/Projects/myapp
pwt init                              # Initialize project

pwt create TICKET-123 main "fix bug"  # Create worktree
pwt use TICKET-123                    # Switch context
pwt use --select                      # Interactive picker
pwt ps1                               # → pwt@TICKET-123
```

### How it feels

```bash
# Open your editor once
pwt editor

# Switch context
pwt use TICKET-456
pwt use TICKET-789
```

Your editor never closes. The code underneath it changes.

That's the whole idea.

---

## Multi-Project

```bash
# Operate on any project from anywhere
pwt myapp list
pwt myapp create TICKET-123 main
pwt myapp use TICKET-123

# Run commands in a specific worktree
pwt myapp TICKET-123 migrate          # Pwtfile command
pwt myapp TICKET-123 -- npm test      # Shell command
pwt myapp @ console                   # @ = main app
```

---

## Pwtfile

Project-specific hooks.
Think *Makefile*, but for worktree lifecycle.

```bash
# Pwtfile
PORT_BASE=5001

setup() {
    pwtfile_copy ".env"
    pwtfile_symlink "node_modules"
    bundle install
}

server() {
    PORT="$PWT_PORT" npm start
}
```

**Variables:** `$PWT_PORT`, `$PWT_WORKTREE`, `$PWT_BRANCH`, `$PWT_PROJECT`, `$MAIN_APP`

Run `pwt help pwtfile` for full syntax.

---

## Shell Integration

```bash
# Add to ~/.zshrc or ~/.bashrc
eval "$(pwt shell-init zsh)"
```

Enables `pwt cd`, `pwt cd @`, `pwt cd -`, and tab completion.

---

## Everyday Commands

| Command | Description |
|---------|-------------|
| `create <name> [base]` | Create worktree (`-e` editor, `-a` AI, `--clone`) |
| `list` | List worktrees (`--dirty`, `--porcelain`) |
| `use <worktree>` | Switch current symlink |
| `cd <worktree>` | Navigate to worktree (`@` main, `-` previous) |
| `remove <worktree>` | Remove worktree (`--with-branch`) |
| `run <wt> <cmd>` | Run command in worktree |
| `server` | Start dev server (from Pwtfile) |
| `status` | Interactive TUI dashboard |
| `tree --ports` | Visual tree with ports |

---

## Worktree vs Clone

| Mode | When to use |
|------|-------------|
| **Worktree** (default) | Most cases — faster, shares git objects |
| **Clone** (`--clone`) | Submodules, or need same branch checked out twice |

---

## Plugins

Some features ship as plugins:

```bash
pwt aitools context     # Generate AI context
pwt extras benchmark    # Compare disk usage
```

Create your own: `pwt plugin create mycommand`

---

## Documentation

| Resource | Description |
|----------|-------------|
| `pwt help` | Quick command reference |
| `pwt help all` | Full docs (good for LLMs) |
| `man pwt` | Manual page |
| [INSTALL.md](INSTALL.md) | Installation guide |
| [FAQ.md](FAQ.md) | Frequently asked questions |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Contributing

Contributions welcome! Please [open an issue](https://github.com/jonasporto/pwt/issues/new) first to discuss changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.
