#!/usr/bin/env bats
# Tests for the Pwtfile environment() hook and `pwt environment`
#
# A version manager that switches on a shell hook (mise activate, direnv,
# nvm) never fires in the subshell pwt runs commands in. environment()
# prints shell assignments for the worktree, and pwt applies them before
# anything it runs there.

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

# A tool that only exists where environment() puts it on PATH, the way a
# version manager puts the worktree's Ruby or Node there.
make_fake_tool() {
    mkdir -p "$TEST_TEMP_DIR/tools-v2/bin"
    cat >"$TEST_TEMP_DIR/tools-v2/bin/fake-tool" <<'EOF'
#!/bin/sh
echo "fake-tool v2"
EOF
    chmod +x "$TEST_TEMP_DIR/tools-v2/bin/fake-tool"
}

# ============================================
# pwt run
# ============================================

@test "pwt run applies the project Pwtfile's environment()" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export GREETING=hello-from-environment"
}
EOF
    "$PWT_BIN" create WT-ENV HEAD

    run "$PWT_BIN" run WT-ENV sh -c 'echo "[${GREETING:-unset}]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[hello-from-environment]"* ]]
}

@test "environment() runs inside the worktree it is for" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export WHERE='$PWD'"
}
EOF
    "$PWT_BIN" create WT-WHERE HEAD

    run "$PWT_BIN" run WT-WHERE sh -c 'echo "[$WHERE]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[$TEST_WORKTREES/WT-WHERE]"* ]]
}

@test "a PATH set by environment() decides which tool pwt run finds" {
    make_fake_tool
    cat >"$TEST_REPO/Pwtfile" <<EOF
environment() {
    echo "export PATH='$TEST_TEMP_DIR/tools-v2/bin':\"\\\$PATH\""
}
EOF
    "$PWT_BIN" create WT-PATH HEAD

    run "$PWT_BIN" run WT-PATH fake-tool
    [ "$status" -eq 0 ]
    [[ "$output" == *"fake-tool v2"* ]]
}

# ============================================
# Pwtfile commands
# ============================================

@test "a Pwtfile command sees the environment" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export GREETING=hello-from-environment"
}
greet() {
    echo "[${GREETING:-unset}]"
}
EOF
    "$PWT_BIN" create WT-CMD HEAD
    cd "$TEST_WORKTREES/WT-CMD"

    run "$PWT_BIN" greet
    [ "$status" -eq 0 ]
    [[ "$output" == *"[hello-from-environment]"* ]]
}

@test "setup() on create sees the environment" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export GREETING=hello-from-environment"
}
setup() {
    echo "${GREETING:-unset}" >"$PWT_WORKTREE_PATH/.setup_saw"
}
EOF
    "$PWT_BIN" create WT-SETUP HEAD

    [ "$(cat "$TEST_WORKTREES/WT-SETUP/.setup_saw")" = "hello-from-environment" ]
}

@test "a background Pwtfile command sees the environment" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export GREETING=hello-from-environment"
}
server() {
    echo "BG[${GREETING:-unset}]"
}
EOF
    "$PWT_BIN" create WT-BG HEAD
    cd "$TEST_WORKTREES/WT-BG"

    run "$PWT_BIN" server --bg
    [ "$status" -eq 0 ]
    local log_file
    log_file=$(echo "$output" | grep -o '"log":"[^"]*"' | head -1 | sed 's/"log":"//;s/"//')
    [ -n "$log_file" ]

    wait_for "grep -q 'BG\\[' \"$log_file\"" 5
    grep -q "BG\[hello-from-environment\]" "$log_file"
}

# ============================================
# for-each
# ============================================

@test "for-each applies each worktree's own environment" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export WHERE_NAME='$(basename "$PWD")'"
}
EOF
    "$PWT_BIN" create WT-ONE HEAD
    "$PWT_BIN" create WT-TWO HEAD

    run "$PWT_BIN" for-each 'echo "seen=$WHERE_NAME"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"seen=WT-ONE"* ]]
    [[ "$output" == *"seen=WT-TWO"* ]]
}

# ============================================
# Global and project Pwtfiles
# ============================================

@test "the global Pwtfile's environment comes first and the project's wins" {
    cat >"$PWT_DIR/Pwtfile" <<'EOF'
environment() {
    echo "export FROM_GLOBAL=yes"
    echo "export WINNER=global"
}
EOF
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export WINNER=project"
}
EOF
    "$PWT_BIN" create WT-BOTH HEAD

    run "$PWT_BIN" run WT-BOTH sh -c 'echo "global=$FROM_GLOBAL winner=$WINNER"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"global=yes winner=project"* ]]
}

@test "a global environment() alone applies to every project" {
    cat >"$PWT_DIR/Pwtfile" <<'EOF'
environment() {
    echo "export FROM_GLOBAL=yes"
}
EOF
    "$PWT_BIN" create WT-GLOBAL HEAD

    run "$PWT_BIN" run WT-GLOBAL sh -c 'echo "global=${FROM_GLOBAL:-unset}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"global=yes"* ]]
}

# ============================================
# Failure never blocks
# ============================================

@test "a failing environment() warns and the command still runs" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "broken tool output" >&2
    return 3
}
EOF
    "$PWT_BIN" create WT-FAIL HEAD

    run "$PWT_BIN" run WT-FAIL echo "still ran"
    [ "$status" -eq 0 ]
    [[ "$output" == *"still ran"* ]]
    [[ "$output" == *"environment() in"*"failed"* ]]
}

@test "without environment() nothing changes" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
greet() { echo "plain"; }
EOF
    "$PWT_BIN" create WT-NONE HEAD

    run "$PWT_BIN" run WT-NONE sh -c 'echo "[${GREETING:-unset}]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[unset]"* ]]
    [[ "$output" != *"environment()"* ]]
}

# ============================================
# pwt environment
# ============================================

@test "pwt environment prints the worktree's assignments, ready to eval" {
    cat >"$PWT_DIR/Pwtfile" <<'EOF'
environment() {
    echo "export FROM_GLOBAL=yes"
}
EOF
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
environment() {
    echo "export WHERE='$PWD'"
}
EOF
    "$PWT_BIN" create WT-PRINT HEAD

    run "$PWT_BIN" environment WT-PRINT
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "export FROM_GLOBAL=yes" ]
    [ "${lines[1]}" = "export WHERE='$TEST_WORKTREES/WT-PRINT'" ]

    eval "$output"
    [ "$WHERE" = "$TEST_WORKTREES/WT-PRINT" ]
}

@test "pwt environment for an unknown worktree fails with not-found" {
    run "$PWT_BIN" environment NO-SUCH-WT
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}
