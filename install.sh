#!/usr/bin/env bash
set -euo pipefail

REPO_URL_DEFAULT="https://github.com/jonasporto/pwt"
REF_DEFAULT="main"
REF_TYPE_DEFAULT="auto"
PREFIX_DEFAULT="$HOME/.local"

usage() {
    cat << 'USAGE'
Usage: install.sh [options]

Options:
  --prefix <dir>   Install prefix (default: ~/.local)
  --ref <ref>      Git ref to install (default: main)
  --tag            Treat --ref as tag
  --branch         Treat --ref as branch
  --repo <url>     GitHub repo URL or slug (default: https://github.com/jonasporto/pwt)
  --from <dir>     Install from local source directory
  --sha256 <hex>   Verify downloaded tarball checksum
  --no-shell       Skip shell integration instructions
  -h, --help       Show this help

Examples:
  ./install.sh
  ./install.sh --ref v1.2.3 --tag
  ./install.sh --ref main --branch
  ./install.sh --from ~/src/pwt
USAGE
}

is_wsl() {
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        return 0
    fi
    if [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
        return 0
    fi
    return 1
}

detect_os() {
    local uname_s
    uname_s=$(uname -s 2>/dev/null || echo "")
    case "$uname_s" in
        Darwin) echo "macos" ;;
        Linux)
            if is_wsl; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

print_missing_deps() {
    local os="$1"
    shift
    local missing=("$@")

    echo "Missing required tools: ${missing[*]}" >&2
    echo "Install them with your package manager." >&2

    if [ "$os" = "macos" ]; then
        echo "  brew install git jq" >&2
    else
        echo "  Install git and jq with your package manager." >&2
    fi
}

normalize_repo_base() {
    local repo="$1"

    repo="${repo%.git}"

    case "$repo" in
        git@github.com:*)
            repo="https://github.com/${repo#git@github.com:}"
            ;;
        https://github.com/*|http://github.com/*)
            ;;
        */*)
            repo="https://github.com/$repo"
            ;;
        *)
            echo "Invalid repo: $repo" >&2
            return 1
            ;;
    esac

    echo "$repo"
}

resolve_ref_type() {
    local ref="$1"
    local ref_type="$2"

    if [ "$ref_type" = "tag" ] || [ "$ref_type" = "branch" ]; then
        echo "$ref_type"
        return 0
    fi

    case "$ref" in
        main|master|develop)
            echo "branch"
            ;;
        v[0-9]*|V[0-9]*)
            echo "tag"
            ;;
        *)
            echo "branch"
            ;;
    esac
}

verify_sha256() {
    local file="$1"
    local expected="$2"

    if command -v shasum >/dev/null 2>&1; then
        local actual
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
        [ "$actual" = "$expected" ]
        return $?
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        local actual
        actual=$(sha256sum "$file" | awk '{print $1}')
        [ "$actual" = "$expected" ]
        return $?
    fi

    echo "No sha256 tool found (need shasum or sha256sum)." >&2
    return 2
}

install_manual() {
    local src="$1"
    local prefix="$2"

    local bindir="$prefix/bin"
    local libdir="$prefix/lib/pwt"
    local mandir="$prefix/share/man/man1"
    local zsh_comp="$prefix/share/zsh/site-functions"
    local bash_comp="$prefix/share/bash-completion/completions"
    local fish_comp="$prefix/share/fish/vendor_completions.d"
    local share_dir="$prefix/share/pwt"

    mkdir -p "$bindir" "$libdir" "$mandir" "$zsh_comp" "$bash_comp" "$fish_comp" "$share_dir/plugins"

    if command -v install >/dev/null 2>&1; then
        install -m 755 "$src/bin/pwt" "$bindir/pwt"
        for f in "$src"/lib/pwt/*.sh; do
            install -m 644 "$f" "$libdir/"
        done
        install -m 644 "$src/man/pwt.1" "$mandir/pwt.1"
        install -m 644 "$src/completions/_pwt" "$zsh_comp/_pwt"
        install -m 644 "$src/completions/pwt.bash" "$bash_comp/pwt"
        install -m 644 "$src/completions/pwt.fish" "$fish_comp/pwt.fish"
    else
        cp "$src/bin/pwt" "$bindir/pwt"
        chmod 755 "$bindir/pwt"
        cp "$src"/lib/pwt/*.sh "$libdir/"
        chmod 644 "$libdir"/*.sh
        cp "$src/man/pwt.1" "$mandir/pwt.1"
        cp "$src/completions/_pwt" "$zsh_comp/_pwt"
        cp "$src/completions/pwt.bash" "$bash_comp/pwt"
        cp "$src/completions/pwt.fish" "$fish_comp/pwt.fish"
    fi

    if [ -d "$src/plugins" ]; then
        cp -R "$src/plugins"/* "$share_dir/plugins/" 2>/dev/null || true
    fi
}

PREFIX="$PREFIX_DEFAULT"
REF="$REF_DEFAULT"
REF_TYPE="$REF_TYPE_DEFAULT"
REPO_URL="$REPO_URL_DEFAULT"
REPO_BASE=""
SRC_DIR=""
SHOW_SHELL_INSTRUCTIONS=true
SHA256=""

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --ref)
            REF="$2"
            shift 2
            ;;
        --tag)
            REF_TYPE="tag"
            shift
            ;;
        --branch)
            REF_TYPE="branch"
            shift
            ;;
        --repo)
            REPO_URL="$2"
            shift 2
            ;;
        --from)
            SRC_DIR="$2"
            shift 2
            ;;
        --sha256)
            SHA256="$2"
            shift 2
            ;;
        --no-shell)
            SHOW_SHELL_INSTRUCTIONS=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

PREFIX="${PREFIX/#\~/$HOME}"
if [ -n "$SRC_DIR" ]; then
    SRC_DIR="${SRC_DIR/#\~/$HOME}"
fi

OS_NAME=$(detect_os)

missing=()
for cmd in git jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    print_missing_deps "$OS_NAME" "${missing[@]}"
    exit 1
fi

SRC_PATH=""
CLEANUP_DIR=""
TARBALL_FILE=""

if [ -n "$SRC_DIR" ]; then
    if [ ! -d "$SRC_DIR" ]; then
        echo "Source directory not found: $SRC_DIR" >&2
        exit 1
    fi
    SRC_PATH="$SRC_DIR"
elif [ -f "./bin/pwt" ] && [ -d "./lib/pwt" ]; then
    SRC_PATH="$(pwd)"
else
    if ! command -v tar >/dev/null 2>&1; then
        echo "tar is required to install from release tarball." >&2
        exit 1
    fi

    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_CMD="curl -fsSL"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget -qO-"
    else
        echo "curl or wget is required to download the release tarball." >&2
        exit 1
    fi

    REPO_BASE=$(normalize_repo_base "$REPO_URL")
    REF_TYPE=$(resolve_ref_type "$REF" "$REF_TYPE")

    if [ "$REF_TYPE" = "tag" ]; then
        REF_PATH="tags/$REF"
    else
        REF_PATH="heads/$REF"
    fi

    TARBALL_URL="$REPO_BASE/archive/refs/$REF_PATH.tar.gz"

    CLEANUP_DIR=$(mktemp -d)
    TARBALL_FILE="$CLEANUP_DIR/pwt.tar.gz"

    $DOWNLOAD_CMD "$TARBALL_URL" > "$TARBALL_FILE"

    if [ -n "$SHA256" ]; then
        if ! verify_sha256 "$TARBALL_FILE" "$SHA256"; then
            echo "Checksum verification failed." >&2
            exit 1
        fi
    else
        echo "Warning: no checksum provided. Use --sha256 to verify the download." >&2
    fi

    tar -xzf "$TARBALL_FILE" -C "$CLEANUP_DIR"
    SRC_PATH=$(find "$CLEANUP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
fi

cleanup() {
    if [ -n "$CLEANUP_DIR" ] && [ -d "$CLEANUP_DIR" ]; then
        rm -rf "$CLEANUP_DIR"
    fi
}
trap cleanup EXIT

if [ -z "$SRC_PATH" ] || [ ! -d "$SRC_PATH" ]; then
    echo "Install source not found." >&2
    exit 1
fi

if [ -f "$SRC_PATH/Makefile" ] && command -v make >/dev/null 2>&1; then
    make -C "$SRC_PATH" install PREFIX="$PREFIX"
else
    install_manual "$SRC_PATH" "$PREFIX"
fi

BIN="$PREFIX/bin/pwt"

if [ ! -x "$BIN" ]; then
    echo "Install finished, but $BIN was not found." >&2
    exit 1
fi

if [ "$SHOW_SHELL_INSTRUCTIONS" = true ]; then
    echo ""
    echo "Shell integration:"
    case "${SHELL:-}" in
        */zsh)
            echo "  eval \"\$(pwt shell-init zsh)\""
            ;;
        */bash)
            echo "  eval \"\$(pwt shell-init bash)\""
            ;;
        */fish)
            echo "  pwt shell-init fish | source"
            ;;
        *)
            echo "  eval \"\$(pwt shell-init)\""
            ;;
    esac
    echo ""
    echo "Verify:"
    echo "  $BIN --version"
    echo "  $BIN doctor"
fi
