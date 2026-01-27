# Installation Guide

## Requirements

- **bash** 4.0+ (default on Linux, needs upgrade on older macOS)
- **git** 2.5+ (for worktree support)
- **jq** (JSON processing)
- **fzf** (optional, for interactive selection)

## Quick Install

### macOS (Homebrew)

```bash
# Add the tap and install
brew tap jonasporto/pwt
brew install pwt

# Or install directly from the formula URL
brew install --HEAD https://raw.githubusercontent.com/jonasporto/pwt/main/Formula/pwt.rb
```

### macOS/Linux (Manual)

```bash
# Clone the repository
git clone https://github.com/jonasporto/pwt.git ~/.pwt-src

# Install with make
cd ~/.pwt-src
make install PREFIX=~/.local

# Or install to /usr/local (requires sudo)
sudo make install
```

### Linux (Package Managers)

#### Ubuntu/Debian

```bash
# Install dependencies
sudo apt-get install bash jq git fzf

# Clone and install
git clone https://github.com/jonasporto/pwt.git
cd pwt
sudo make install
```

#### Arch Linux (AUR)

```bash
# Using yay
yay -S pwt-git

# Or manually
git clone https://github.com/jonasporto/pwt.git
cd pwt
sudo make install
```

#### Fedora/RHEL

```bash
# Install dependencies
sudo dnf install bash jq git fzf

# Clone and install
git clone https://github.com/jonasporto/pwt.git
cd pwt
sudo make install
```

### npm (Cross-platform)

```bash
# Install globally
npm install -g @jonasporto/pwt

# Or with npx (no install)
npx @jonasporto/pwt help
```

### Windows (WSL)

pwt is designed for Unix-like systems. On Windows, use WSL (Windows Subsystem for Linux):

```bash
# In WSL terminal
sudo apt-get install bash jq git
git clone https://github.com/jonasporto/pwt.git
cd pwt
sudo make install
```

## Shell Setup

### Zsh (recommended)

Add to `~/.zshrc`:

```bash
# If installed to ~/.local
export PATH="$HOME/.local/bin:$PATH"

# Enable completions
fpath=(~/.local/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit

# Optional: shell integration for auto-cd
eval "$(pwt shell-init zsh)"
```

### Bash

Add to `~/.bashrc`:

```bash
# If installed to ~/.local
export PATH="$HOME/.local/bin:$PATH"

# Optional: shell integration
eval "$(pwt shell-init bash)"
```

## Verify Installation

```bash
# Check version
pwt --version

# Run health check
pwt doctor

# Initialize your first project
cd your-project
pwt init
```

## Upgrading

### Homebrew

```bash
brew upgrade pwt
```

### Manual

```bash
cd ~/.pwt-src
git pull
make install PREFIX=~/.local
```

## Uninstalling

### Homebrew

```bash
brew uninstall pwt
```

### Manual

```bash
make uninstall PREFIX=~/.local
# Or
sudo make uninstall
```

## Troubleshooting

### "command not found: pwt"

Ensure the install directory is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"  # or /usr/local/bin
```

### Completions not working

1. Check fpath includes the completions directory
2. Rebuild completion cache: `rm -f ~/.zcompdump* && compinit`

### "jq: command not found"

Install jq:
- macOS: `brew install jq`
- Ubuntu: `sudo apt-get install jq`
- Fedora: `sudo dnf install jq`

### Old bash version on macOS

macOS ships with bash 3.x. Upgrade with Homebrew:

```bash
brew install bash
# Add to /etc/shells and change shell, or just use it for pwt
```
