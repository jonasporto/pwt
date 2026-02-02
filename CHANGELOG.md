# Changelog

All notable changes to pwt (Power Worktrees) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-26

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
