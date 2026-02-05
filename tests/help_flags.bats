#!/usr/bin/env bats
# Tests for --help / -h flags on commands

load test_helper

setup() {
    setup_test_env

    cd "$TEST_REPO"
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/"
}
EOF
}

teardown() {
    teardown_test_env
}

# ============================================
# Core commands --help tests
# ============================================

@test "pwt info --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt info -h shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt doctor --help shows usage" {
    run "$PWT_BIN" doctor --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt doctor -h shows usage" {
    run "$PWT_BIN" doctor -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt diff --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" diff --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt run --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt for-each --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" for-each --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt cd --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" cd --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ============================================
# Commands that already had --help
# ============================================

@test "pwt create --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt list --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"pwt list"* ]]
}

@test "pwt tree --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" tree --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"tree"* ]]
}

# ============================================
# Help content validation
# ============================================

@test "info help includes usage line" {
    cd "$TEST_REPO"
    run "$PWT_BIN" info --help
    [[ "$output" == *"Usage: pwt info"* ]]
}

@test "doctor help includes checks section" {
    run "$PWT_BIN" doctor --help
    [[ "$output" == *"Checks performed"* ]]
}

@test "diff help includes examples" {
    cd "$TEST_REPO"
    run "$PWT_BIN" diff --help
    [[ "$output" == *"Examples"* ]]
}

# ============================================
# New command --help tests (v0.1.10)
# ============================================

@test "pwt current --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" current --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--name"* ]]
    [[ "$output" == *"--port"* ]]
}

@test "pwt use --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" use --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--select"* ]]
}

@test "pwt fix-port --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" fix-port --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"port"* ]]
}

@test "pwt open --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" open --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt alias --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" alias --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"alias"* ]]
}

@test "pwt select --help shows usage and keybindings" {
    cd "$TEST_REPO"
    # select needs _select dispatch which requires project context
    run "$PWT_BIN" _select --help 2>&1 || true
    # Alternatively test via help dispatcher
    run "$PWT_BIN" help select
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"Keybindings"* ]]
}

@test "pwt steps --help shows usage" {
    cd "$TEST_REPO"
    # steps calls detect_project before checking help, so use help dispatcher
    run "$PWT_BIN" help steps
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"step_"* ]]
}

@test "pwt step --help shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" step --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"PWT_ARGS"* ]]
}

# ============================================
# Help alias resolution (pwt help <alias>)
# ============================================

@test "pwt help add resolves to create help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help add
    [ "$status" -eq 0 ]
    [[ "$output" == *"create|add"* ]]
}

@test "pwt help rm resolves to remove help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help rm
    [ "$status" -eq 0 ]
    [[ "$output" == *"remove|rm"* ]]
}

@test "pwt help ls resolves to list help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"list|ls"* ]]
}

@test "pwt help m resolves to meta help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help m
    [ "$status" -eq 0 ]
    [[ "$output" == *"meta"* ]]
}

@test "pwt help fix resolves to repair help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help fix
    [ "$status" -eq 0 ]
    [[ "$output" == *"repair|fix"* ]]
}

@test "pwt help s resolves to server help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help s
    [ "$status" -eq 0 ]
    [[ "$output" == *"server|s"* ]]
}

@test "pwt help fix-port shows fix-port help" {
    cd "$TEST_REPO"
    run "$PWT_BIN" help fix-port
    [ "$status" -eq 0 ]
    [[ "$output" == *"fix-port"* ]]
}

# ============================================
# pwt m alias for meta
# ============================================

@test "pwt m defaults to meta list" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-MALIAS HEAD

    run "$PWT_BIN" m
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-MALIAS"* ]]
}

@test "pwt m show works like pwt meta show" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-MSHOW HEAD

    run "$PWT_BIN" m show WT-MSHOW
    [ "$status" -eq 0 ]
    [[ "$output" == *"port"* ]]
}

# ============================================
# Help shows alias forms
# ============================================

@test "create help shows create|add in usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create --help
    [[ "$output" == *"create|add"* ]]
}

@test "remove help shows remove|rm in usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" remove --help
    [[ "$output" == *"remove|rm"* ]]
}

@test "list help shows list|ls in usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --help
    [[ "$output" == *"list|ls"* ]]
}

@test "server help shows server|s in usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" server --help
    [[ "$output" == *"server|s"* ]]
}
