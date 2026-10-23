#!/usr/bin/env bats
# pwt create --detach and pwt repoint: worktrees pinned to exact commits

load test_helper
bats_require_minimum_version 1.5.0

setup() {
    setup_test_env
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    # 48000-48499: own range
    export TEST_BASE_PORT=$((48000 + (RANDOM % 9) * 50))
    mkdir -p "$TEST_WORKTREES"
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
base_port=$TEST_BASE_PORT
EOF
    cd "$TEST_REPO"
    echo one >app.txt
    git add app.txt
    git commit -q -m "one"
    export C1
    C1=$(git rev-parse HEAD)
    mkdir -p db/migrate
    echo two >app.txt
    echo "create" >db/migrate/001_create.rb
    git add -A
    git commit -q -m "two"
    export C2
    C2=$(git rev-parse HEAD)
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
repoint() {
    set -u
    echo "prev=$PWT_PREVIOUS_COMMIT"
    printf 'changed:%s\n' "$PWT_CHANGED_FILES"
    pwt_changed 'db/migrate/*' && pwt_step db echo "migrating"
    pwt_changed Gemfile.lock || pwt_step deps --skip "lockfile unchanged"
    [ -f "$MAIN_APP/.hook-fails" ] && return 9
    return 0
}
longtask() { sleep 30; }
EOF
}

teardown() {
    "$PWT_BIN" jobs stop --all >/dev/null 2>&1 || true
    kill_test_jobs
    teardown_test_env
}

@test "create --detach checks out the exact commit with no branch" {
    run "$PWT_BIN" create SLOT "$C1" --detach
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detached at: ${C1:0:7}"* ]]
    [ "$(git -C "$TEST_WORKTREES/SLOT" rev-parse HEAD)" = "$C1" ]
    run git -C "$TEST_WORKTREES/SLOT" symbolic-ref -q HEAD
    [ "$status" -ne 0 ]
    ! git show-ref --verify --quiet refs/heads/test/SLOT
    [ "$(sed -n 's/^branch=//p' "$PWT_DIR/state/test-project/SLOT.meta")" = "" ]
    [ -n "$(sed -n 's/^port=//p' "$PWT_DIR/state/test-project/SLOT.meta")" ]
}

@test "create --detach needs a ref and refuses --branch" {
    run "$PWT_BIN" create SLOT --detach
    [ "$status" -eq 2 ]
    run "$PWT_BIN" create SLOT "$C1" --detach --branch x
    [ "$status" -eq 2 ]
}

@test "create --detach exits 3 for an unknown ref" {
    run "$PWT_BIN" create SLOT deadbeefdeadbeef --detach
    [ "$status" -eq 3 ]
}

@test "repoint moves the worktree, keeps its port, runs repoint() with what changed" {
    "$PWT_BIN" create SLOT "$C1" --detach >/dev/null
    local port
    port=$(sed -n 's/^port=//p' "$PWT_DIR/state/test-project/SLOT.meta")
    touch "$TEST_WORKTREES/SLOT/untracked-cache.bin"

    run "$PWT_BIN" repoint SLOT "$C2"
    [ "$status" -eq 0 ]
    [ "$(git -C "$TEST_WORKTREES/SLOT" rev-parse HEAD)" = "$C2" ]
    [ "$(sed -n 's/^port=//p' "$PWT_DIR/state/test-project/SLOT.meta")" = "$port" ]
    [ -f "$TEST_WORKTREES/SLOT/untracked-cache.bin" ]
    [[ "$output" == *"prev=$C1"* ]]
    [[ "$output" == *"changed:app.txt"* ]]
    [[ "$output" == *"migrating"* ]]
    [[ "$output" == *"2 files changed"* ]]
}

@test "repoint --progress json streams the steps" {
    "$PWT_BIN" create SLOT "$C1" --detach >/dev/null
    run --separate-stderr "$PWT_BIN" repoint SLOT "$C2" --progress json
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *'"step":"repoint","state":"start"'* ]]
    [[ "$output" == *'"step":"checkout","state":"done"'*'"detail":"2 files changed"'* ]]
    [[ "$output" == *'"step":"db","state":"done"'* ]]
    [[ "$output" == *'"step":"deps","state":"skip"'* ]]
    [[ "${lines[${#lines[@]} - 1]}" == *'"step":"repoint","state":"done"'* ]]
    [[ "$output" != *"migrating"* ]] # hook output is on stderr
}

@test "repoint refuses (exit 4) while a pwt job runs for the worktree, unless --stop" {
    "$PWT_BIN" create SLOT "$C1" --detach >/dev/null
    "$PWT_BIN" --bg test-project SLOT longtask >/dev/null

    run "$PWT_BIN" repoint SLOT "$C2"
    [ "$status" -eq 4 ]
    [[ "$output" == *"running pwt jobs"* ]]
    [ "$(git -C "$TEST_WORKTREES/SLOT" rev-parse HEAD)" = "$C1" ]

    run "$PWT_BIN" repoint SLOT "$C2" --stop
    [ "$status" -eq 0 ]
    [ "$(git -C "$TEST_WORKTREES/SLOT" rev-parse HEAD)" = "$C2" ]
}

@test "repoint refuses (exit 4) with uncommitted changes to tracked files" {
    "$PWT_BIN" create SLOT "$C1" --detach >/dev/null
    echo dirty >"$TEST_WORKTREES/SLOT/app.txt"
    run "$PWT_BIN" repoint SLOT "$C2"
    [ "$status" -eq 4 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "repoint exits 3 for an unknown ref or worktree" {
    "$PWT_BIN" create SLOT "$C1" --detach >/dev/null
    run "$PWT_BIN" repoint SLOT no-such-ref
    [ "$status" -eq 3 ]
    run "$PWT_BIN" repoint NOPE "$C2"
    [ "$status" -eq 3 ]
}

@test "a failing repoint() exits 1 after the checkout" {
    "$PWT_BIN" create SLOT "$C1" --detach >/dev/null
    touch "$TEST_REPO/.hook-fails"
    run --separate-stderr "$PWT_BIN" repoint SLOT "$C2" --progress json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"step":"repoint","state":"fail"'* ]]
    [ "$(git -C "$TEST_WORKTREES/SLOT" rev-parse HEAD)" = "$C2" ]
}

@test "repoint works on a worktree created on a branch" {
    "$PWT_BIN" create ONBRANCH "$C1" >/dev/null
    run "$PWT_BIN" repoint ONBRANCH "$C2"
    [ "$status" -eq 0 ]
    run git -C "$TEST_WORKTREES/ONBRANCH" symbolic-ref -q HEAD
    [ "$status" -ne 0 ]
    grep -q $'\trepoint\t' "$PWT_DIR/events.log"
}

@test "repoint ignores a typechange (a tracked file setup replaced with a symlink)" {
    echo "notes" >"$TEST_REPO/NOTES.md"
    git -C "$TEST_REPO" add NOTES.md
    git -C "$TEST_REPO" commit -q -m notes
    local c3 c4
    c3=$(git -C "$TEST_REPO" rev-parse HEAD)
    echo three >"$TEST_REPO/app.txt"
    git -C "$TEST_REPO" commit -q -am three
    c4=$(git -C "$TEST_REPO" rev-parse HEAD)
    "$PWT_BIN" create SLOT "$c3" --detach >/dev/null
    echo "shared" >"$TEST_TEMP_DIR/shared-notes.md"
    rm "$TEST_WORKTREES/SLOT/NOTES.md"
    ln -s "$TEST_TEMP_DIR/shared-notes.md" "$TEST_WORKTREES/SLOT/NOTES.md"

    run "$PWT_BIN" repoint SLOT "$c4"
    [ "$status" -eq 0 ]
    [ "$(git -C "$TEST_WORKTREES/SLOT" rev-parse HEAD)" = "$c4" ]
    [ -L "$TEST_WORKTREES/SLOT/NOTES.md" ]

    # A real edit is still refused
    echo edit >"$TEST_WORKTREES/SLOT/app.txt"
    run "$PWT_BIN" repoint SLOT "$c3"
    [ "$status" -eq 4 ]
}

@test "create --no-use leaves the current worktree alone" {
    "$PWT_BIN" create FIRST HEAD >/dev/null
    [ "$("$PWT_BIN" current --name 2>/dev/null)" = "FIRST" ]
    "$PWT_BIN" create SLOT "$C1" --detach --no-use >/dev/null
    [ "$("$PWT_BIN" current --name 2>/dev/null)" = "FIRST" ]
}
