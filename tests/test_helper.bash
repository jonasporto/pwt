#!/usr/bin/env bash
# Test helper for pwt tests
# Sets up the environment and provides utility functions

# Get the path to pwt binary and module library
PWD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PWT_BIN="$PWD_DIR/bin/pwt"
PWT_LIB_DIR="$PWD_DIR/lib/pwt"

_pwt_build_test_repo() {
    local dest="$1"
    mkdir -p "$dest"
    git init -q "$dest"
    git -C "$dest" config user.email "test@test.com"
    git -C "$dest" config user.name "Test User"
    # No background maintenance: it drops lock files into .git/objects
    # after a commit, and a cp -R of this repo mid-maintenance dies on
    # "maintenance.lock: No such file or directory" (seen on macOS CI)
    git -C "$dest" config maintenance.auto false
    git -C "$dest" config gc.auto 0
    touch "$dest/README.md"
    git -C "$dest" add README.md
    git -C "$dest" commit -q -m "Initial commit"
}

# Create a temporary directory for each test
setup_test_env() {
    export TEST_TEMP_DIR=$(mktemp -d)
    export HOME="$TEST_TEMP_DIR/home"
    # Use PWT_DIR env var for sandbox testing (pwt respects this)
    export PWT_DIR="$TEST_TEMP_DIR/pwt"
    # The update notice reads a tty to decide whether to speak, and a test
    # harness may hand pwt one. Tests must never depend on that, and must
    # never reach the network: disable it explicitly rather than by luck.
    export PWT_NO_UPDATE_CHECK=1
    mkdir -p "$HOME"
    mkdir -p "$PWT_DIR/projects"
    # State contract v2: declare schema so pwt skips legacy-migration checks
    echo '2' > "$PWT_DIR/state-version"

    # Create a temporary git repo for testing. Every test needs one, so the
    # init+config+commit sequence is done once per bats process and copied
    # per test: a cp -R of a tiny repo is several times cheaper, and a copy
    # is exactly as isolated as a fresh init. Falls back to building in
    # place on bats < 1.4 (no BATS_*_TMPDIR).
    export TEST_REPO="$TEST_TEMP_DIR/test-repo"
    local tmpl_root="${BATS_SUITE_TMPDIR:-${BATS_FILE_TMPDIR:-}}"
    if [ -n "$tmpl_root" ]; then
        local tmpl="$tmpl_root/pwt-template-repo"
        # BATS_SUITE_TMPDIR is shared by every parallel bats process, so
        # the template must appear atomically: build it under a unique
        # name and rename into place. A process that loses the race sees
        # a complete template, never one still being committed to.
        if [ ! -d "$tmpl/.git" ]; then
            local build
            build=$(mktemp -d "$tmpl_root/pwt-template-build.XXXXXX")
            _pwt_build_test_repo "$build/repo"
            mv "$build/repo" "$tmpl" 2>/dev/null || true
            rm -rf "$build"
        fi
        cp -R "$tmpl" "$TEST_REPO"
    else
        _pwt_build_test_repo "$TEST_REPO"
    fi
    cd "$TEST_REPO"
}

# Clean up temporary directory after each test
teardown_test_env() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Source specific functions from pwt for unit testing
# This extracts a function from pwt without running the whole script.
# Extraction greps+seds the whole ~7000-line binary, so files that pull in a
# dozen functions per test were rescanning it dozens of times per test: the
# extracted snippet is cached per bats process (tmpdirs are wiped per run,
# and bin/pwt cannot change mid-run, so staleness is impossible).
source_pwt_function() {
    local func_name="$1"
    local cache_root="${BATS_SUITE_TMPDIR:-${BATS_FILE_TMPDIR:-}}"
    if [ -n "$cache_root" ]; then
        local snip="$cache_root/pwt-func-cache/$func_name.sh"
        if [ ! -f "$snip" ]; then
            mkdir -p "$cache_root/pwt-func-cache"
            {
                grep -E '^(RED|GREEN|YELLOW|BLUE|NC)=' "$PWT_BIN" | head -5
                # Shared pattern constants, so an extracted function matches
                # against the same list the real script uses (an undefined
                # regex in [[ =~ ]] matches everything, which would make a
                # test pass for the wrong reason)
                grep -E '^PWT_[A-Z_]+_RE=' "$PWT_BIN"
                sed -n "/^$func_name()/,/^}/p" "$PWT_BIN"
            } >"$snip"
        fi
        # shellcheck disable=SC1090
        source "$snip"
        return
    fi
    # Extract colors and the function definition from pwt
    eval "$(grep -E '^(RED|GREEN|YELLOW|BLUE|NC)=' "$PWT_BIN" | head -5)"
    eval "$(grep -E '^PWT_[A-Z_]+_RE=' "$PWT_BIN")"
    eval "$(sed -n "/^$func_name()/,/^}/p" "$PWT_BIN")"
}

# Source multiple functions at once
source_pwt_functions() {
    for func in "$@"; do
        source_pwt_function "$func"
    done
}

# Assert function output equals expected
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected' but got '$actual'}"

    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $message" >&2
        return 1
    fi
}

# Assert function returns true (exit 0)
assert_success() {
    local message="${1:-Expected success but got failure}"
    if [ "$status" -ne 0 ]; then
        echo "FAIL: $message (exit code: $status)" >&2
        return 1
    fi
}

# Assert function returns false (exit non-zero)
assert_failure() {
    local message="${1:-Expected failure but got success}"
    if [ "$status" -eq 0 ]; then
        echo "FAIL: $message" >&2
        return 1
    fi
}

# Poll a condition instead of fixed sleeps (keeps tests fast)
# Usage: wait_for "<command>" [timeout_seconds]
wait_for() {
    local cmd="$1"
    local timeout="${2:-5}"
    local tries
    tries=$(awk "BEGIN { print int($timeout / 0.05) }")
    while [ "$tries" -gt 0 ]; do
        if eval "$cmd" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.05
        tries=$((tries - 1))
    done
    return 1
}

# Kill every background job this test's PWT_DIR launched, whole session:
# a job script is a session leader running $PWT_DIR/jobs/<id>.sh, and its
# server is a child that outlives a TERM to the leader alone. Works without
# lsof (minimal Linux), where a teardown cannot find leftovers by port.
kill_test_jobs() {
    [ -n "${PWT_DIR:-}" ] || return 0
    local pid
    for pid in $(ps -eo pid=,args= 2>/dev/null | awk -v d="$PWT_DIR/jobs/" '$2 == "/bin/bash" && index($3, d) == 1 { print $1 }'); do
        kill -9 -- "-$pid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
    done
}

# Kill a process and all its descendants (children first)
kill_tree() {
    local root="$1" kids
    kids=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$root" '$2 == p { print $1 }')
    local k
    for k in $kids; do
        kill_tree "$k"
    done
    kill -9 "$root" 2>/dev/null || true
}
