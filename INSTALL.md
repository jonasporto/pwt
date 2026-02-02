# Installation Guide

## Requirements

- **bash** 3.2+ (default on macOS/Linux/WSL)
- **git** 2.5+ (for worktree support)
- **jq** (JSON processing)
- **make** (required for source install)
- **fzf** (optional but highly recommended, for interactive selection)
- **lsof** (optional but highly recommended, for port detection)

**Windows:** supported via **WSL** only (native Windows shell is not supported).

## Install

### macOS (Homebrew) - recommended

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

### No repo (curl, macOS/Linux/WSL)

```bash
curl -fsSL https://raw.githubusercontent.com/jonasporto/pwt/main/install.sh -o /tmp/pwt-install.sh
less /tmp/pwt-install.sh
bash /tmp/pwt-install.sh --ref vX.Y.Z --tag --sha256 <sha256>
# or latest from main (no checksum)
bash /tmp/pwt-install.sh --ref main --branch
```

### From source

```bash
# Clone the repository
git clone https://github.com/jonasporto/pwt.git ~/.pwt-src

# Install to ~/.local (recommended)
cd ~/.pwt-src
make install PREFIX=~/.local

# Or install system-wide (requires sudo)
sudo make install
```

### Dependencies

**macOS:**
```bash
brew install git jq make fzf
```

**Linux/WSL:** install `git`, `jq`, `make`, `fzf`, and `lsof` with your package manager.

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

- Homebrew: `brew upgrade pwt`
- npm: `npm i -g @jonasporto/pwt`
- curl install: re-run `install.sh` with the desired `--ref`
- source install: `git pull` then `make install PREFIX=~/.local`

## Uninstalling

- Homebrew: `brew uninstall pwt`
- npm: `npm rm -g @jonasporto/pwt`
- curl/source install: remove `~/.local/bin/pwt` and `~/.local/lib/pwt` (or the prefix you used)

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

Install jq with your package manager (macOS: `brew install jq`).

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
