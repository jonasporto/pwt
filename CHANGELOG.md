# Changelog

All notable changes to pwt (Power Worktrees) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.10] - 2026-02-05

### Added
- **Description in create**: `pwt create TICKET "auth login bug"` - quoted text with spaces is auto-detected as description
- **Meta shortcut**: `pwt meta <key> [value]` for quick get/set on current worktree
  - `pwt meta description` - get description
  - `pwt meta description "my task"` - set description
  - `pwt meta "text with spaces"` - shorthand for setting description
- **Description search in cd**: `pwt cd <term>` now searches both name and description
  - Supports multi-word search: `pwt cd "auth login"` finds "fixing auth login bug"
  - Case-insensitive partial matching
  - Single match navigates directly; multiple/zero matches → fzf fallback
- **Interactive query flag**: `pwt select --query <text>` to pre-filter fzf results
- **Short alias**: `pwt m` as alias for `pwt meta`
- **Background execution**: `--bg` flag to daemonize Pwtfile commands (e.g., `pwt server --bg`)
  - Uses perl double-fork + setsid for reliable process detachment
  - Outputs JSON with job_id, pid, and log file path
  - Duplicate job detection prevents running same command twice
- **Non-interactive mode**: `--no-input` flag closes stdin and sets `PWT_AGENT=1`
  - Designed for CI/CD and AI agent workflows
  - Prevents interactive prompts from blocking automated processes
- **Job management**: `pwt jobs` command to manage background jobs
  - `pwt jobs list` - show all running/stopped jobs
  - `pwt jobs logs <id> [-f]` - view/follow job output
  - `pwt jobs stop <id>` - stop a running job
  - `pwt jobs stop --all` - stop all jobs
  - `pwt jobs clean` - remove stale entries
- **PWT_AGENT variable**: Exported to Pwtfiles (defaults to `0`, set to `1` with `--no-input`)
- **Help for all commands**: Every command now supports `-h`/`--help`
  - Added help to: current, use, fix-port, select, steps, step, repair, port, open, alias
  - `pwt help <alias>` resolves aliases (add→create, rm→remove, ls→list, fix→repair, m→meta, s→server)

### Changed
- Comprehensive `pwt meta` help with ASCII diagrams showing where metadata appears
- Help text shows alias forms: `Usage: pwt create|add`, `pwt remove|rm`, `pwt list|ls`, etc.
- `@` (main app) documented consistently across info, editor, ai help texts
- Flag ordering standardized to `-short|--long` pattern (cmd_select)
- Trailing slash normalization added to cmd_run and cmd_open (shell completion compat)

### Fixed
- `pwt help <command>` now correctly dispatches to module commands (create, remove, list, etc.)

### Internal
- Extracted `get_worktree_port()` helper to deduplicate port lookup with legacy fallback
- New `lib/pwt/jobs.sh` module for background job state management
- `_strip_pwt_execution_flags()` helper strips --bg/--no-input from PWT_ARGS
- Fixed `cmd_server` dispatch to pass all args (was losing flags like --sidekiq)

## [0.1.9] - 2026-02-03

### Added
- Quick demo video (GIF and MP4) in README

### Changed
- Updated README with demo-aligned command examples
- Simplified Everyday Commands table

### Removed
- Formula folder (moved to separate homebrew-pwt tap)
- Examples folder (replaced by main demo)

## [0.1.0] - 2026-02-02

### Added
- **Initial public release**
- **Core commands**: create, remove, list, cd, use, current, info
- **Worktree management**: Git worktrees with port allocation
- **Clone mode**: `--clone` flag for full isolation when needed
- **Pwtfile**: Project-local workflow file (setup/server/teardown)
- **Global Pwtfile**: `~/.pwt/Pwtfile` for shared commands across projects
- **Interactive selection**: `pwt select` and `pwt pick` with fzf
- **Interactive TUI**: `pwt status` command with htop-like dashboard
- **Shell integration**: `pwt shell-init` for bash/zsh/fish
- **Plugin system**: `pwt plugin install/remove/create`
- **Built-in plugins**: pwt-aitools, pwt-extras
- **Claude Code integration**: `pwt claude-setup` and `pwt ai` commands
- **Distribution**: Homebrew formula, npm package, and Makefile
- **Shell completions**: Bash, Fish, and Zsh completions
- **Man page**: Full manual page (`man pwt`)
- **Test suite**: 530+ tests with BATS framework
- **CI/CD**: GitHub Actions for automated testing

[Unreleased]: https://github.com/jonasporto/pwt/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jonasporto/pwt/releases/tag/v0.1.0
