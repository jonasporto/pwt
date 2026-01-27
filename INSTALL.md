# Installation Guide

## Requirements

- **bash** 3.2+ (default on macOS and Linux)
- **git** 2.5+ (for worktree support)
- **jq** (JSON processing)
- **fzf** (optional, for interactive selection)

## Quick Install

```bash
# Clone the repository
git clone https://github.com/jonasporto/pwt.git ~/.pwt-src

# Install to ~/.local (recommended)
cd ~/.pwt-src
make install PREFIX=~/.local

# Or install system-wide (requires sudo)
sudo make install
```

### Install Dependencies

**macOS:**
```bash
brew install jq fzf
```

**Ubuntu/Debian:**
```bash
sudo apt-get install jq git fzf
```

**Fedora/RHEL:**
```bash
sudo dnf install jq git fzf
```

## Shell Setup

### Zsh (recommended)

Add to `~/.zshrc`:

```bash
# Add to PATH (if installed to ~/.local)
export PATH="$HOME/.local/bin:$PATH"

# Enable completions
fpath=(~/.local/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit

# Enable shell integration (for pwt cd)
eval "$(pwt shell-init zsh)"
```

### Bash

Add to `~/.bashrc`:

```bash
# Add to PATH (if installed to ~/.local)
export PATH="$HOME/.local/bin:$PATH"

# Enable completions
source ~/.local/share/bash-completion/completions/pwt

# Enable shell integration (for pwt cd)
eval "$(pwt shell-init bash)"
```

### Fish

Add to `~/.config/fish/config.fish`:

```fish
# Add to PATH (if installed to ~/.local)
fish_add_path ~/.local/bin

# Shell integration
pwt shell-init fish | source
```

## Verify Installation

```bash
pwt --version      # Check version
pwt doctor         # Run health check
man pwt            # View manual
```

## Upgrading

```bash
cd ~/.pwt-src
git pull
make install PREFIX=~/.local
```

## Uninstalling

```bash
cd ~/.pwt-src
make uninstall PREFIX=~/.local
# Or if installed system-wide:
sudo make uninstall
```

## Troubleshooting

### "command not found: pwt"

Ensure the install directory is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this line to your `~/.zshrc` or `~/.bashrc`.

### Completions not working

1. Verify completions are installed: `ls ~/.local/share/zsh/site-functions/_pwt`
2. Rebuild completion cache: `rm -f ~/.zcompdump* && compinit`

### "jq: command not found"

Install jq:
- macOS: `brew install jq`
- Ubuntu: `sudo apt-get install jq`
- Fedora: `sudo dnf install jq`

## Alternative Installation (Development)

If you just want to try pwt without installing:

```bash
git clone https://github.com/jonasporto/pwt.git
cd pwt

# Run directly
./bin/pwt --version

# Or add to PATH temporarily
export PATH="$PWD/bin:$PATH"
export PWT_LIB="$PWD/lib/pwt"
pwt doctor
```
