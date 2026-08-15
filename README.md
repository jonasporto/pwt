# pwt - Power Worktrees

**A powerful Git worktree workflow for today's multi-project development.**

[![Tests](https://github.com/jonasporto/pwt/actions/workflows/test.yml/badge.svg)](https://github.com/jonasporto/pwt/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.1-green.svg)](CHANGELOG.md)

## Demos

![Quick Start](examples/gifs/01-quickstart.gif)
![Use Symlink](examples/gifs/02-use-symlink.gif)

[Watch overview (mp4)](examples/videos/00-overview.mp4)

More demos in `examples/` (tapes in `examples/tapes`, gifs in `examples/gifs`, how to record in `examples/README.md`).

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

## When pwt beats raw `git worktree`

| You are hitting | pwt answer |
|-----------------|------------|
| "Port already in use" running dev servers on two branches | A stable port per worktree (`$PWT_PORT`), servers started with it |
| Several agents/people on the same repo, branches switching underneath | One isolated worktree each, jump with `pwt <worktree>` |
| Fresh checkout fails until `.env`/deps/symlinks are hand-copied | `setup()` hook runs on every create/adopt (Pwtfile) |
| Scripts sleep-polling for a server or job | `pwt server wait --log-contains`, `pwt jobs wait` (exit 5 on timeout) |
| Starting a server hangs the agent's shell | `pwt server --bg` daemonizes; `pwt jobs list --porcelain` tracks it |
| Parsing human-formatted CLI output | `--porcelain`/`--json` everywhere + a stable exit-code contract |
| Browser tests need one URL while the target branch changes | `pwt gateway` routes a stable URL to any worktree |

A one-off second checkout with no server and no setup? Raw `git worktree
add` is fine — pwt earns its keep when the lifecycle around the worktree
(ports, setup, servers, jobs) is the problem.

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

**Dependencies:** `git` (required). `fzf`, `lsof` (optional but highly recommended). `jq` is only needed once, to convert state written before schema v2.

See [INSTALL.md](INSTALL.md) for shell setup and troubleshooting.

---

## Quick Start

```bash
cd ~/projects/myapp
pwt init                        # Initialize project
pwt add feat/user-auth          # Create worktree from branch
pwt feat/user-auth              # Jump to a worktree
pwt cd --select                 # Interactive worktree picker
pwt list                        # List worktrees with git status
```

### Custom commands (Pwtfile)

```bash
pwt editor                      # Open editor in current worktree
pwt build                       # Run build command
pwt server                      # Start dev server (auto port allocation)
pwt gateway up --port 5999      # Start stable project gateway daemon
pwt gateway use feat/user-auth  # Route gateway to a worktree server
pwt servers                     # Show active project servers
```

---

## Multi-Project

```bash
# See all configured projects
pwt project

# Jump to a worktree in another project
pwt backend security-patch

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

`pwt` core stays project-agnostic: it manages worktrees, metadata, port
allocation, navigation, background job bookkeeping, and delegation. Project
details such as dependency installation, databases, asset watchers, queues,
tests, and cleanup commands belong in the Pwtfile.

```bash
# Pwtfile
PORT_BASE=5001

setup() {
    pwtfile_copy ".env.local"
    pwtfile_symlink ".cache"
    # ignore generated files repo-locally (.git/info/exclude: never
    # committed, one call covers every worktree of the repo)
    pwtfile_git_exclude "pnpm-lock.yaml" "pnpm-workspace.yaml"
    ./scripts/setup
}

server() {
    case "${1:-start}" in
        start) exec env PORT="$PWT_PORT" ./scripts/dev ;;
        stop) ./scripts/dev-stop ;;
    esac
}

# Runs as part of `pwt doctor`: pwt checks the machine and the worktree
# layout, the project checks whatever "healthy" means for its own stack.
doctor() {
    [ -d node_modules ] || echo "⚠ dependencies not installed"
    [ -s .npmrc ] || echo "⚠ .npmrc is empty (registry auth missing)"
}
```

Command params are available as `$1`, `$2`, etc. and as raw `$PWT_ARGS`.
Remove cleanup can delegate to any Pwtfile command with `--kill-<command>`;
for example, `pwt remove FEATURE --kill-worker` calls `worker --kill`.

A project can also own its branch-naming convention with a `branch_name()`
hook: it receives the worktree name and description and prints the branch to
create (`--branch` always wins, and returning nothing falls back to pwt's
default). See `examples/Pwtfile.reference` for the full semantics.

Pwtfile commands can be called with progressively less context:

```bash
pwt <project> <worktree> <command> [args...]  # From anywhere
pwt <worktree> <command> [args...]            # From inside the project
pwt <command> [args...]                       # From inside the worktree
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
| `add <branch>` | Create worktree from branch (`-e` editor) |
| `track <remote-branch>` | Create worktree tracking an existing remote branch |
| `adopt [path]` | Register an existing worktree and run setup |
| `list` | List worktrees with git status (`--dirty`) |
| `cd <worktree>` | Navigate to worktree (`@` main, `-` previous, `--select`) |
| `project` | List all configured projects |
| `<worktree>` | Navigate to worktree inside the current project |
| `<project> <worktree>` | Jump to worktree in another project |
| `editor` | Open editor in current worktree |
| `server` | Start dev server (from Pwtfile) |
| `server wait [worktree]` | Block until the server is ready (`--log-contains`, `--timeout`) |
| `jobs wait <id\|worktree>` | Block until a background job finishes (`--timeout`) |
| `gateway` | Stable project URL that routes to a worktree server |
| `servers` | Show active servers, gateway target, and background jobs |
| `logs [worktree]` | Show background job logs (`-f` to follow) |
| `self` | List installed pwt versions / switch active (`self use <target>`) |
| `remove <worktree>` | Remove worktree (`--with-branch`) |
| `state --json` | Versioned JSON snapshot of all pwt state (projects, worktrees, jobs) |

---

## Existing Remote Branches

Use `track` when you want to edit an existing remote branch directly without applying your configured `branch_prefix`:

```bash
pwt track origin/team/PROJ-1234
```

This creates a worktree named `PROJ-1234`, a local branch named `team/PROJ-1234`, configures tracking to `origin/team/PROJ-1234`, allocates metadata/port, and runs normal setup hooks.

Override the worktree name when the branch does not contain a clear ticket:

```bash
pwt track origin/team/fix-login-flow --name login-flow
```

Equivalent explicit `create` form:

```bash
pwt create PROJ-1234 --branch team/PROJ-1234 --from origin/team/PROJ-1234
```

If a worktree was already created with raw Git, adopt it into pwt:

```bash
pwt adopt /path/to/worktree
# or, from inside it
pwt setup
```

Adopted worktrees can live outside the configured `worktrees_dir`. pwt records
their real path in metadata, allocates a port, runs normal setup hooks, and then
includes them in `pwt list`, `pwt list --names`, `pwt cd`, `pwt use`,
`pwt current`, and `pwt info`.

---

## Stable Gateway

Each worktree keeps its own allocated port, but you can also run one stable
project-scoped gateway URL and switch which worktree it targets:

```bash
pwt gateway up --port 5999 --host localhost
pwt gateway use PROJ-1234
open "$(pwt gateway url)"
```

`pwt gateway up` runs a small local proxy daemon for the current project.
`pwt gateway use <worktree>` points new connections at that worktree's
allocated server port. If the target port is not listening and the project
Pwtfile defines `server()`, pwt starts it with `pwt server <worktree> --bg`
before switching the gateway.

The public gateway URL defaults to `localhost` so browser cookies and sessions
are shared with direct local app URLs such as `http://localhost:5001`. Set
`gateway_host` or pass `--host` when a project should use another loopback
hostname or IP:

```bash
pwt config gateway_host 127.0.0.1
pwt gateway up --port 5999 --host app.localhost
```

Custom hosts must resolve to loopback and may need to be allowed by the app's
development host configuration. The proxy still binds to loopback only.

Gateways are scoped by project:

```bash
pwt gateway down          # current project
pwt backend gateway down  # explicit project/alias from anywhere
```

Use `pwt servers` to see the gateway, current target, running server jobs, and
active ports. Add `--all` to include stopped worktrees.

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
pwt statusline install  # Claude Code statusline
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

### For agents

Driving pwt from an AI agent or a script? Run **`pwt skill`** to print the
agent guide (or `pwt skill --install` to copy it into `~/.claude/skills` and
`~/.agents/skills`). It covers: machine-readable flags
(`list --porcelain`, `info --porcelain`, `gateway status --json`,
`pwt state --json`, `--no-input`), the exit-code table, and the wait
primitives (`pwt server wait`, `pwt jobs wait`) that replace poll loops.

External tools can also read pwt state directly: `~/.pwt` holds flat
key=value files plus an append-only `events.log`, versioned via
`~/.pwt/state-version` — see
[docs/state-v2-contract.md](docs/state-v2-contract.md).

---

## Contributing

Contributions welcome! Please [open an issue](https://github.com/jonasporto/pwt/issues/new) first to discuss changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

---

## License

[MIT](LICENSE) © Jonas Porto

Found a security issue? See [SECURITY.md](SECURITY.md) — please report it
privately rather than opening an issue.
