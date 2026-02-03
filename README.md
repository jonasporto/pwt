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
cd ~/projects/myapp
pwt init                        # Initialize project
pwt add feat/user-auth          # Create worktree from branch
pwt cd --select                 # Interactive worktree picker
pwt list                        # List worktrees with git status
```

### Custom commands (Pwtfile)

```bash
pwt editor                      # Open editor in current worktree
pwt build                       # Run build command
pwt server                      # Start dev server (auto port allocation)
pwt ai                          # Start AI coding assistant
```

---

## Multi-Project

```bash
# See all configured projects
pwt project

# Jump to a worktree in another project
pwt backend cd security-patch

# Quick switch to another project's main
pwt backend

# Run commands in any project
pwt backend build
pwt backend server
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
| `init` | Initialize project in current repo |
| `add <branch>` | Create worktree from branch (`-e` editor, `-a` AI) |
| `list` | List worktrees with git status (`--dirty`) |
| `cd <worktree>` | Navigate to worktree (`@` main, `-` previous, `--select`) |
| `project` | List all configured projects |
| `<project> cd <wt>` | Jump to worktree in another project |
| `editor` | Open editor in current worktree |
| `server` | Start dev server (from Pwtfile) |
| `ai` | Start AI coding assistant |
| `remove <worktree>` | Remove worktree (`--with-branch`) |

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
