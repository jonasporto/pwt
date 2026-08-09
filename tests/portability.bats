#!/usr/bin/env bats
# Tests for cross-platform fallbacks (Linux/WSL boxes without macOS tools)

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================
# align_columns (pure-bash replacement for column -t)
# ============================================

_load_align() {
    sed -n '/^align_columns() {/,/^}/p' "$PWT_BIN" >"$BATS_TEST_TMPDIR/align.sh"
    # shellcheck source=/dev/null
    source "$BATS_TEST_TMPDIR/align.sh"
}

@test "align_columns pads columns to the widest cell" {
    _load_align
    run bash -c "source '$BATS_TEST_TMPDIR/align.sh'; printf 'a|bbbb|c\nlonger|b|ccc\n' | align_columns"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "a       bbbb  c" ]]
    [[ "${lines[1]}" == "longer  b     ccc" ]]
}

@test "align_columns keeps the last cell unpadded and intact" {
    _load_align
    run bash -c "source '$BATS_TEST_TMPDIR/align.sh'; printf 'x|y|zzz\n' | align_columns"
    [ "$status" -eq 0 ]
    [[ "$output" == *"zzz" ]]
    [[ "$output" != *"zzz "* ]]
}

@test "align_columns handles empty input without error" {
    _load_align
    run bash -c "source '$BATS_TEST_TMPDIR/align.sh'; printf '' | align_columns"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "align_columns handles rows with a single column" {
    _load_align
    run bash -c "source '$BATS_TEST_TMPDIR/align.sh'; printf 'solo\nalso\n' | align_columns"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "solo" ]]
    [[ "${lines[1]}" == "also" ]]
}

@test "pwt does not call column(1) anywhere" {
    run grep -nE '\| *column -t' "$PWT_BIN"
    [ "$status" -ne 0 ]
}

# ============================================
# open_path (macOS open / Linux xdg-open / WSL wslview)
# ============================================

@test "open_path is defined and used by cmd_open" {
    run grep -n '^open_path()' "$PWT_BIN"
    [ "$status" -eq 0 ]

    run grep -n 'open_path "\$worktree_path"' "$PWT_BIN"
    [ "$status" -eq 0 ]
}

@test "pwt open does not hardcode bare open(1)" {
    run grep -nE '^\s+open "\$worktree_path"' "$PWT_BIN"
    [ "$status" -ne 0 ]
}

@test "open_path reports a clear error when no opener exists" {
    run env PATH="/nonexistent" /bin/bash -c "
        RED=''; YELLOW=''; BLUE=''; NC=''
        $(sed -n '/^open_path() {/,/^}/p' "$PWT_BIN")
        open_path /tmp
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"No file manager opener found"* ]]
}

# ============================================
# Port detection without lsof
# ============================================

@test "get_pids_on_port falls back to ss or fuser when lsof is absent" {
    run grep -n 'command -v ss' "$PWT_BIN"
    [ "$status" -eq 0 ]

    run grep -n 'command -v fuser' "$PWT_BIN"
    [ "$status" -eq 0 ]
}

@test "is_port_free probes /dev/tcp when lsof is unavailable" {
    run grep -n 'dev/tcp/127.0.0.1' "$PWT_BIN"
    [ "$status" -eq 0 ]
}

@test "is_port_free detects an occupied port without lsof" {
    local port=$((46000 + RANDOM % 900))

    # Listener detached from bats' fds (perl double-fork, as used elsewhere)
    perl -e '
        use POSIX qw(setsid);
        use IO::Socket::INET;
        my $port = shift;
        my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => $port,
                                      Listen => 5, ReuseAddr => 1) or exit 1;
        my $pid = fork();
        exit 0 if $pid;
        setsid();
        open(STDIN, "<", "/dev/null");
        open(STDOUT, ">", "/dev/null");
        open(STDERR, ">&STDOUT");
        sleep 10;
    ' "$port" 2>/dev/null || skip "perl listener unavailable"

    sleep 0.5

    run bash -c "
        _lsof_available='no'
        $(sed -n '/^has_lsof() {/,/^}/p' "$PWT_BIN")
        $(sed -n '/^get_pids_on_port() {/,/^}/p' "$PWT_BIN")
        $(sed -n '/^is_port_free() {/,/^}/p' "$PWT_BIN")
        is_port_free $port
    "
    [ "$status" -eq 1 ]
}

@test "is_port_free reports a free port as free without lsof" {
    local port=$((46900 + RANDOM % 90))
    run bash -c "
        _lsof_available='no'
        $(sed -n '/^has_lsof() {/,/^}/p' "$PWT_BIN")
        $(sed -n '/^get_pids_on_port() {/,/^}/p' "$PWT_BIN")
        $(sed -n '/^is_port_free() {/,/^}/p' "$PWT_BIN")
        is_port_free $port
    "
    [ "$status" -eq 0 ]
}

# ============================================
# Interactive picker without fzf
# ============================================

@test "pick_fallback returns the single candidate without prompting" {
    run bash -c "
        pwt_error() { echo \"\$*\" >&2; }
        $(sed -n '/^pick_fallback() {/,/^}/p' "$PWT_BIN")
        printf 'only-one|main|x\n' | pick_fallback 'Pick'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "only-one|main|x" ]]
}

@test "pick_fallback narrows by initial query before prompting" {
    run bash -c "
        pwt_error() { echo \"\$*\" >&2; }
        $(sed -n '/^pick_fallback() {/,/^}/p' "$PWT_BIN")
        printf 'alpha|a\nbeta|b\ngamma|c\n' | pick_fallback 'Pick' 'beta'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "beta|b" ]]
}

@test "pick_fallback fails cleanly on empty input" {
    run bash -c "
        pwt_error() { echo \"\$*\" >&2; }
        $(sed -n '/^pick_fallback() {/,/^}/p' "$PWT_BIN")
        printf '' | pick_fallback 'Pick'
    "
    [ "$status" -eq 1 ]
}

@test "select and use --select no longer hard-require fzf" {
    run grep -n 'is required for pwt select' "$PWT_BIN"
    [ "$status" -ne 0 ]

    run grep -n 'is required for pwt use --select' "$PWT_BIN"
    [ "$status" -ne 0 ]

    run grep -n '^pick_fallback()' "$PWT_BIN"
    [ "$status" -eq 0 ]
}
