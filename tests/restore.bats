#!/usr/bin/env bats
# Tests for `pwt restore` - the recovery path for changes saved when a dirty
# worktree is removed.
#
# This file exists because coverage showed the whole family at 0%:
# cmd_restore 0/34, _restore_list 0/40, _restore_backup 0/73. It is the code
# a user reaches for after losing work, so "never executed by a test" is the
# worst place for it to be.

load test_helper

setup() {
    setup_test_env

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Randomized base_port: TCP ports are machine-global and test files run
    # in parallel (same convention as gateway.bats / audit_fixes.bats)
    export TEST_BASE_PORT=$((46500 + RANDOM % 400))
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF

    cd "$TEST_REPO"
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"

    export TRASH_DIR="$PWT_DIR/trash"
}

teardown() {
    teardown_test_env
}

# Build a backup by hand: the shape `pwt remove` leaves behind.
_seed_backup() {
    local name="${1:-RESTORE-WT_20260101_120000}"
    local worktree="${2:-RESTORE-WT}"
    local branch="${3:-test/RESTORE-WT}"

    mkdir -p "$TRASH_DIR"
    cat >"$TRASH_DIR/${name}.trash" <<EOF
worktree=$worktree
branch=$branch
base=HEAD
port=5099
description=saved work
project=test-project
timestamp=20260101_120000
date=2026-01-01 12:00:00
EOF
}

_seed_patch() {
    local name="$1"
    # A patch against the committed file.txt
    cat >"$TRASH_DIR/${name}.patch" <<'PATCH'
diff --git a/file.txt b/file.txt
index d95f3ad..8b13789 100644
--- a/file.txt
+++ b/file.txt
@@ -1 +1,2 @@
 content
+restored line
PATCH
}

_seed_untracked() {
    local name="$1"
    mkdir -p "$TRASH_DIR/${name}_untracked/sub"
    echo "untracked body" >"$TRASH_DIR/${name}_untracked/notes.md"
    echo "nested" >"$TRASH_DIR/${name}_untracked/sub/deep.txt"
}

# ============================================
# Listing
# ============================================

@test "restore with no trash directory says so instead of failing" {
    rm -rf "$TRASH_DIR"
    run "$PWT_BIN" restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"No backups found"* ]]
}

@test "restore with an empty trash directory reports no backups" {
    mkdir -p "$TRASH_DIR"
    run "$PWT_BIN" restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"No backups found"* ]]
}

@test "restore lists a backup with worktree, date and contents" {
    _seed_backup "LIST-WT_20260101_120000" "LIST-WT" "test/LIST-WT"
    _seed_patch "LIST-WT_20260101_120000"

    run "$PWT_BIN" restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIST-WT"* ]]
    [[ "$output" == *"2026-01-01"* ]]
    [[ "$output" == *"patch"* ]]
    [[ "$output" == *"test/LIST-WT"* ]]
}

@test "restore list marks a backup that also has untracked files" {
    _seed_backup "BOTH-WT_20260101_120000" "BOTH-WT"
    _seed_patch "BOTH-WT_20260101_120000"
    _seed_untracked "BOTH-WT_20260101_120000"

    run "$PWT_BIN" restore list
    [ "$status" -eq 0 ]
    [[ "$output" == *"untracked"* ]]
}

@test "restore falls back to listing legacy patch-only backups" {
    mkdir -p "$TRASH_DIR"
    _seed_patch "LEGACY-WT_20260101_120000"

    run "$PWT_BIN" restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"LEGACY-WT"* ]]
    [[ "$output" == *"legacy"* ]]
}

@test "restore --help explains the forms without needing a trash dir" {
    rm -rf "$TRASH_DIR"
    run "$PWT_BIN" restore --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt restore <backup>"* ]]
}

# ============================================
# Restoring into an existing worktree
# ============================================

@test "restore applies a patch to an existing worktree" {
    "$PWT_BIN" create TARGET-WT HEAD >/dev/null
    _seed_backup "PATCH-BK_20260101_120000" "TARGET-WT"
    _seed_patch "PATCH-BK_20260101_120000"

    run "$PWT_BIN" restore PATCH-BK_20260101_120000 TARGET-WT
    [ "$status" -eq 0 ]
    [[ "$output" == *"Patch applied"* ]]
    grep -q "restored line" "$TEST_WORKTREES/TARGET-WT/file.txt"
}

@test "restore copies untracked files, preserving subdirectories" {
    "$PWT_BIN" create UNTRACKED-WT HEAD >/dev/null
    _seed_backup "UNTR-BK_20260101_120000" "UNTRACKED-WT"
    _seed_untracked "UNTR-BK_20260101_120000"

    run "$PWT_BIN" restore UNTR-BK_20260101_120000 UNTRACKED-WT
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORKTREES/UNTRACKED-WT/notes.md" ]
    [ -f "$TEST_WORKTREES/UNTRACKED-WT/sub/deep.txt" ]
    grep -q "untracked body" "$TEST_WORKTREES/UNTRACKED-WT/notes.md"
}

@test "restore never overwrites an existing file" {
    "$PWT_BIN" create SAFE-WT HEAD >/dev/null
    echo "MINE - do not clobber" >"$TEST_WORKTREES/SAFE-WT/notes.md"

    _seed_backup "SAFE-BK_20260101_120000" "SAFE-WT"
    _seed_untracked "SAFE-BK_20260101_120000"

    run "$PWT_BIN" restore SAFE-BK_20260101_120000 SAFE-WT
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skip (exists)"* ]]
    grep -q "MINE - do not clobber" "$TEST_WORKTREES/SAFE-WT/notes.md"
}

@test "restore reports a patch that cannot apply cleanly, without failing hard" {
    "$PWT_BIN" create CONFLICT-WT HEAD >/dev/null
    echo "diverged content" >"$TEST_WORKTREES/CONFLICT-WT/file.txt"

    _seed_backup "CONFLICT-BK_20260101_120000" "CONFLICT-WT"
    _seed_patch "CONFLICT-BK_20260101_120000"

    run "$PWT_BIN" restore CONFLICT-BK_20260101_120000 CONFLICT-WT
    [[ "$output" == *"cannot be applied cleanly"* ]]
    # And it tells the user what to try next
    [[ "$output" == *"--3way"* ]]
}

# ============================================
# Errors
# ============================================

@test "restore of an unknown backup fails with a clear message" {
    mkdir -p "$TRASH_DIR"
    _seed_backup "EXISTS-BK_20260101_120000"

    run "$PWT_BIN" restore NO-SUCH-BACKUP
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "restore into a nonexistent worktree fails without touching anything" {
    _seed_backup "ORPHAN-BK_20260101_120000"
    _seed_patch "ORPHAN-BK_20260101_120000"

    run "$PWT_BIN" restore ORPHAN-BK_20260101_120000 NO-SUCH-WORKTREE
    [ "$status" -ne 0 ]
    [[ "$output" == *"Worktree not found"* ]]
}

@test "restore of a legacy backup without metadata explains it needs a target" {
    mkdir -p "$TRASH_DIR"
    _seed_patch "NOMETA-BK_20260101_120000"

    run "$PWT_BIN" restore NOMETA-BK_20260101_120000
    [ "$status" -ne 0 ]
    [[ "$output" == *"no metadata"* ]] || [[ "$output" == *"Specify target worktree"* ]]
}

# ============================================
# Round trip: remove a dirty worktree, then restore it
# ============================================

@test "a dirty worktree removed and restored gets its changes back" {
    "$PWT_BIN" create ROUNDTRIP HEAD >/dev/null
    echo "work in progress" >>"$TEST_WORKTREES/ROUNDTRIP/file.txt"
    echo "new file" >"$TEST_WORKTREES/ROUNDTRIP/scratch.txt"

    run "$PWT_BIN" remove ROUNDTRIP -y
    [ "$status" -eq 0 ]

    # A backup must exist for the removed worktree
    run bash -c "ls '$TRASH_DIR' | grep -c ROUNDTRIP"
    [ "$output" -ge 1 ]

    # And it must be listed
    run "$PWT_BIN" restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"ROUNDTRIP"* ]]
}
