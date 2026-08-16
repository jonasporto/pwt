#!/usr/bin/env bats
# The update notice must reach a human without ever reaching a script:
# cache-only in hot paths, stderr, once a day, never under --no-input.

load test_helper

setup() {
    setup_test_env
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
EOF
    cd "$TEST_REPO"
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    teardown_test_env
}

# Pretend the release API already answered, without touching the network
_seed_cache() {
    printf '%s\n%s\n' "$(date +%s)" "$1" >"$PWT_DIR/version-check"
}

@test "notice text appears when the cached version is newer" {
    source_pwt_functions _pwt_update_notice_text _pwt_version_lt \
        _pwt_upgrade_command _pwt_install_method
    PWT_VERSION="0.0.1"
    PWT_VERSION_CACHE="$PWT_DIR/version-check"
    _seed_cache "9.9.9"

    run _pwt_update_notice_text
    [ "$status" -eq 0 ]
    [[ "$output" == *"9.9.9 is available"* ]]
    [[ "$output" == *"0.0.1"* ]]
}

@test "notice text is empty when the cached version is not newer" {
    source_pwt_functions _pwt_update_notice_text _pwt_version_lt \
        _pwt_upgrade_command _pwt_install_method
    PWT_VERSION="9.9.9"
    PWT_VERSION_CACHE="$PWT_DIR/version-check"
    _seed_cache "0.0.1"

    run _pwt_update_notice_text
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "notice text is empty with no cache at all (no network in hot paths)" {
    source_pwt_functions _pwt_update_notice_text _pwt_version_lt \
        _pwt_upgrade_command _pwt_install_method
    PWT_VERSION="0.0.1"
    PWT_VERSION_CACHE="$PWT_DIR/does-not-exist"

    run _pwt_update_notice_text
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "create never prints the notice into captured output" {
    _seed_cache "99.0.0"
    cd "$TEST_REPO"

    # bats captures output, so there is no tty: the guard must hold and
    # the worktree must still be created normally
    run "$PWT_BIN" create WT-NOTICE HEAD
    [ "$status" -eq 0 ]
    [[ "$output" != *"is available"* ]]
    [ -d "$TEST_WORKTREES/WT-NOTICE" ]
}

@test "create under --no-input stays silent about updates" {
    _seed_cache "99.0.0"
    cd "$TEST_REPO"
    run "$PWT_BIN" --no-input create WT-NOINPUT HEAD
    [ "$status" -eq 0 ]
    [[ "$output" != *"is available"* ]]
}

@test "PWT_NO_UPDATE_CHECK=1 suppresses the notice" {
    source_pwt_functions _pwt_maybe_notify_update _pwt_update_notice_text \
        _pwt_version_lt _pwt_upgrade_command _pwt_install_method
    PWT_VERSION="0.0.1"
    PWT_VERSION_CACHE="$PWT_DIR/version-check"
    _seed_cache "9.9.9"
    PWT_NO_UPDATE_CHECK=1

    run _pwt_maybe_notify_update
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$PWT_DIR/version-notified" ]
}

@test "the notice is rate limited to once a day" {
    source_pwt_functions _pwt_maybe_notify_update _pwt_update_notice_text \
        _pwt_version_lt _pwt_upgrade_command _pwt_install_method
    PWT_VERSION="0.0.1"
    PWT_VERSION_CACHE="$PWT_DIR/version-check"
    _seed_cache "9.9.9"
    PWT_NO_UPDATE_CHECK=0
    PWT_NO_INPUT=false
    PWT_AGENT=0

    # A fresh stamp means "already told them today": no second notice, and
    # the stamp must not move
    date +%s >"$PWT_DIR/version-notified"
    local before
    before=$(cat "$PWT_DIR/version-notified")
    run _pwt_maybe_notify_update
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$PWT_DIR/version-notified")" = "$before" ]
}

@test "doctor reports the running version" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt: "* ]]
}

# ============================================
# No cache: the notice must still become possible without ever making
# the caller wait for the network
# ============================================

@test "a cacheless agent run neither notifies nor triggers a refresh" {
    cd "$TEST_REPO"
    rm -f "$PWT_DIR/version-check" "$PWT_DIR/version-check-attempt"

    run "$PWT_BIN" --no-input create WT-NOSPAWN HEAD
    [ "$status" -eq 0 ]
    # No network for automation: not even a background one
    [ ! -f "$PWT_DIR/version-check-attempt" ]
    [[ "$output" != *"is available"* ]]
}

@test "PWT_NO_UPDATE_CHECK=1 prevents the background refresh too" {
    source_pwt_functions _pwt_maybe_notify_update _pwt_update_notice_text \
        _pwt_spawn_version_refresh _pwt_version_lt _pwt_upgrade_command \
        _pwt_install_method
    PWT_VERSION="0.0.1"
    PWT_VERSION_CACHE="$PWT_DIR/version-check"
    PWT_VERSION_CACHE_TTL=18000
    PWT_NO_UPDATE_CHECK=1

    run _pwt_maybe_notify_update
    [ "$status" -eq 0 ]
    [ ! -f "$PWT_DIR/version-check-attempt" ]
}

@test "the background refresh is attempted at most once per TTL" {
    source_pwt_functions _pwt_spawn_version_refresh
    PWT_VERSION_CACHE_TTL=18000

    # A fresh attempt stamp means one is already in flight (or just ran)
    date +%s >"$PWT_DIR/version-check-attempt"
    local before
    before=$(cat "$PWT_DIR/version-check-attempt")
    run _pwt_spawn_version_refresh
    [ "$status" -eq 0 ]
    [ "$(cat "$PWT_DIR/version-check-attempt")" = "$before" ]
}

@test "the internal refresh command writes the cache and stays silent" {
    cd "$TEST_REPO"
    rm -f "$PWT_DIR/version-check"

    run "$PWT_BIN" _refresh-version-cache
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    # Offline machines simply get no cache; the command must not fail
    if [ -f "$PWT_DIR/version-check" ]; then
        head -1 "$PWT_DIR/version-check" | grep -qE '^[0-9]+$'
    fi
}
