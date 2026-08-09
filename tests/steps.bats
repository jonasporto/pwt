#!/usr/bin/env bats
# Tests for `pwt step` / `pwt steps`
# Focus: the argument contract between pwt and step_* functions

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

# Regression: `pwt step <name> <arg>` must forward positionals. A step that
# its setup() calls with an argument needs the same argument here; pwt cannot
# invent project-specific values such as a database suffix.
@test "step forwards positional arguments to the function" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
step_echo_args() {
    echo "POS1=[${1:-<none>}] ARGS=[$PWT_ARGS]"
}
EOF

    cd "$TEST_REPO"
    run "$PWT_BIN" step echo_args _wt42
    [ "$status" -eq 0 ]
    [[ "$output" == *"POS1=[_wt42]"* ]]
    [[ "$output" == *"ARGS=[_wt42]"* ]]
}

@test "step forwards several positional arguments in order" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
step_pair() {
    echo "ONE=[${1:-}] TWO=[${2:-}]"
}
EOF

    cd "$TEST_REPO"
    run "$PWT_BIN" step pair alpha beta
    [ "$status" -eq 0 ]
    [[ "$output" == *"ONE=[alpha] TWO=[beta]"* ]]
}

@test "step runs a function that takes no arguments" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
step_plain() {
    echo "PLAIN_RAN"
}
EOF

    cd "$TEST_REPO"
    run "$PWT_BIN" step plain
    [ "$status" -eq 0 ]
    [[ "$output" == *"PLAIN_RAN"* ]]
}

@test "step help documents that args arrive as positionals" {
    run "$PWT_BIN" step --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'"$1"'* ]]
    [[ "$output" == *"unbound variable"* ]]
}

@test "steps lists step_ functions without the prefix" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
step_alpha() { :; }
step_beta() { :; }
server() { :; }
EOF

    cd "$TEST_REPO"
    run "$PWT_BIN" steps
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
    [[ "$output" != *"step_alpha"* ]]
}
