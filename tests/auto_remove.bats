#!/usr/bin/env bats
# Tests for `pwt auto-remove` (alias: cleanup) - bulk removal of worktrees
# whose branches are already merged.
#
# Written because coverage showed cmd_auto_remove at 10/113: a command that
# deletes worktrees in bulk, exercised only by its --help. The safety
# properties below (dry-run by default, --execute required to actually
# remove, uncommitted work never destroyed, unmerged branches kept) are
# exactly the ones that must not regress silently.

load test_helper

setup() {
    setup_test_env

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    export TEST_BASE_PORT=$((46000 + RANDOM % 400))
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF

    # auto-remove compares against origin/<target>, so the fixture needs a
    # real remote to fetch from.
    export ORIGIN_DIR="$TEST_TEMP_DIR/origin.git"
    git init -q --bare "$ORIGIN_DIR"

    cd "$TEST_REPO"
    git branch -m main 2>/dev/null || true
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"
    git remote add origin "$ORIGIN_DIR"
    git push -q origin main
}

teardown() {
    teardown_test_env
}

# A worktree whose branch is already contained in origin/main.
_merged_worktree() {
    local name="$1"
    "$PWT_BIN" create "$name" HEAD >/dev/null
}

# A worktree with a commit that origin/main does not have.
_unmerged_worktree() {
    local name="$1"
    "$PWT_BIN" create "$name" HEAD >/dev/null
    echo "ahead" >"$TEST_WORKTREES/$name/ahead.txt"
    git -C "$TEST_WORKTREES/$name" add ahead.txt
    git -C "$TEST_WORKTREES/$name" commit -q -m "Unmerged work"
}

# ============================================
# Safety
# ============================================

@test "auto-remove refuses a bare non-interactive run" {
    _merged_worktree AR-SAFE

    # Without a terminal the command must be invoked deliberately, so that
    # nobody reaches a bulk removal by accident from a script.
    run "$PWT_BIN" auto-remove main
    [ "$status" -ne 0 ]
    [[ "$output" == *"SAFETY"* ]]
    [ -d "$TEST_WORKTREES/AR-SAFE" ]
}

@test "auto-remove --dry-run previews without removing" {
    _merged_worktree AR-DRY

    run "$PWT_BIN" auto-remove main --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
    [[ "$output" == *"AR-DRY"* ]]
    [ -d "$TEST_WORKTREES/AR-DRY" ]
}

@test "auto-remove --help does not need a remote or worktrees" {
    run "$PWT_BIN" auto-remove --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run by default"* ]]
}

@test "auto-remove rejects an unknown option" {
    run "$PWT_BIN" auto-remove --bogus-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

# ============================================
# Classification
# ============================================

@test "auto-remove marks a merged worktree and keeps an unmerged one" {
    _merged_worktree AR-MERGED
    _unmerged_worktree AR-AHEAD

    run "$PWT_BIN" auto-remove main --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"MERGED"* ]]
    [[ "$output" == *"AR-MERGED"* ]]
    [[ "$output" == *"PENDING"* ]]
    [[ "$output" == *"AR-AHEAD"* ]]
}

@test "auto-remove flags a merged-but-dirty worktree instead of removing it" {
    _merged_worktree AR-DIRTY
    echo "uncommitted" >>"$TEST_WORKTREES/AR-DIRTY/file.txt"

    run "$PWT_BIN" auto-remove main --execute
    [ "$status" -eq 0 ]
    [[ "$output" == *"DIRTY"* ]]
    [[ "$output" == *"AR-DIRTY"* ]]
    # Uncommitted work is never destroyed by a bulk command
    [ -d "$TEST_WORKTREES/AR-DIRTY" ]
    grep -q "uncommitted" "$TEST_WORKTREES/AR-DIRTY/file.txt"
}

@test "auto-remove reports nothing to do when every worktree is ahead" {
    _unmerged_worktree AR-ONLY-AHEAD

    run "$PWT_BIN" auto-remove main --execute
    [ "$status" -eq 0 ]
    [[ "$output" == *"No worktrees to remove"* ]]
    [ -d "$TEST_WORKTREES/AR-ONLY-AHEAD" ]
}

@test "auto-remove handles an empty worktrees directory" {
    run "$PWT_BIN" auto-remove main --execute
    [ "$status" -eq 0 ]
    [[ "$output" == *"No worktrees found"* ]]
}

# ============================================
# Execution
# ============================================

@test "auto-remove --execute removes merged worktrees and leaves the rest" {
    _merged_worktree AR-GONE-1
    _merged_worktree AR-GONE-2
    _unmerged_worktree AR-STAYS

    run "$PWT_BIN" auto-remove main --execute
    [ "$status" -eq 0 ]

    [ ! -d "$TEST_WORKTREES/AR-GONE-1" ]
    [ ! -d "$TEST_WORKTREES/AR-GONE-2" ]
    [ -d "$TEST_WORKTREES/AR-STAYS" ]
}

@test "auto-remove clears metadata for the worktrees it removed" {
    _merged_worktree AR-META

    run "$PWT_BIN" auto-remove main --execute
    [ "$status" -eq 0 ]
    [ ! -f "$PWT_DIR/state/test-project/AR-META.meta" ]
}

@test "auto-remove -y is accepted as an alias for --execute" {
    _merged_worktree AR-ALIAS

    run "$PWT_BIN" auto-remove main -y
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/AR-ALIAS" ]
}

@test "cleanup is an alias for auto-remove" {
    _merged_worktree AR-CLEANUP

    run "$PWT_BIN" cleanup main --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"AR-CLEANUP"* ]]
    [ -d "$TEST_WORKTREES/AR-CLEANUP" ]
}

# ============================================
# Errors
# ============================================

@test "auto-remove fails clearly when the target branch is not on the remote" {
    _merged_worktree AR-NOBRANCH

    run "$PWT_BIN" auto-remove no-such-branch --execute
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found on remote"* ]]
    # Nothing removed on the error path
    [ -d "$TEST_WORKTREES/AR-NOBRANCH" ]
}
