# Changelog

All notable changes to pwt (Power Worktrees) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-01-26

### Added
- **Distribution**: Homebrew formula, npm package, and Makefile for installation
- **Shell completions**: Bash, Fish, and Zsh completions
- **Man page**: Full manual page (`man pwt`)
- **Modular architecture**: Split into lib/pwt modules for maintainability
- **Test suite**: 530+ tests with BATS framework
- **CI/CD**: GitHub Actions for automated testing

### Changed
- Standardized all error messages to use `pwt_error()` function
- Improved project detection in shell completions
- Better handling of partial project name matches

### Removed
- Dead code: unused functions `list_metadata`, `get_project_dir`, `run_project_hook`

## [0.9.0] - 2025-01-25

### Added
- **Interactive TUI**: `pwt status` command with htop-like dashboard
- **Main app as worktree**: Treat `@` as a worktree for all commands
- **Auto-tracking**: `--guess-remote` flag for `pwt create`
- **Shell integration**: `pwt shell-init` for seamless navigation

### Changed
- Improved `pwt list` output with better status indicators
- Enhanced port allocation to avoid conflicts

## [0.8.0] - 2025-01-20

### Added
- **Claude Code integration**: `pwt claude-setup` command
- **Status line**: Custom format for Claude Code status bar
- **AI tools support**: `pwt ai` command for various AI assistants

### Changed
- Better error messages with context
- Improved Pwtfile variable exports

## [0.7.0] - 2025-01-15

### Added
- **Interactive selection**: `pwt select` and `pwt pick` with fzf
- **Worktree diff**: `pwt diff` to compare worktrees
- **File copy**: `pwt copy` to copy files between worktrees
- **Restore**: `pwt restore` to recover from trash

### Changed
- `pwt remove` now backs up uncommitted changes to trash

## [0.6.0] - 2025-01-10

### Added
- **Plugin system**: `pwt plugin install/remove/create`
- **Built-in plugins**: pwt-aitools, pwt-extras
- **Project aliases**: Short names for projects

### Changed
- Configuration moved to `~/.pwt/projects/` structure

## [0.5.0] - 2025-01-05

### Added
- **Auto-remove**: `pwt auto-remove` for merged worktrees
- **Port fixing**: `pwt fix-port` for conflict resolution
- **Repair command**: `pwt repair` to fix broken worktrees

### Changed
- Improved port allocation algorithm
- Better branch detection

## [0.4.0] - 2024-12-28

### Added
- **For-each**: `pwt for-each` to run commands in all worktrees
- **Run command**: `pwt run` for specific worktree context
- **Shell command**: `pwt shell` for interactive shell

### Changed
- Pwtfile commands now receive all PWT_* variables

## [0.3.0] - 2024-12-20

### Added
- **Project management**: `pwt project` command
- **Multiple projects**: Support for managing multiple repos
- **Config command**: `pwt config` for project settings

### Changed
- Metadata stored per-project in JSON files

## [0.2.0] - 2024-12-15

### Added
- **Tree view**: `pwt tree` for visual display
- **Editor integration**: `pwt editor` command
- **Doctor command**: `pwt doctor` for health checks

### Changed
- Improved list output with git status

## [0.1.0] - 2024-12-10

### Added
- Initial release
- Basic worktree management: create, remove, list
- Port allocation system
- Pwtfile support for custom commands
- Server command for development
- Zsh completions

[Unreleased]: https://github.com/jonasporto/pwt/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jonasporto/pwt/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/jonasporto/pwt/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/jonasporto/pwt/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/jonasporto/pwt/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/jonasporto/pwt/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/jonasporto/pwt/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/jonasporto/pwt/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jonasporto/pwt/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jonasporto/pwt/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jonasporto/pwt/releases/tag/v0.1.0
