#!/usr/bin/env bats
# Tests for pwt topology command
# Verifies topology analysis help and basic invocation
# Note: Full analysis uses AI and is not suitable for automated tests

load test_helper

setup() {
    setup_test_env

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/"
}
EOF

    # Add a commit
    cd "$TEST_REPO"
    echo "content" > file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    teardown_test_env
}

# ============================================
# topology help
# ============================================

@test "pwt topology --help shows usage" {
    run "$PWT_BIN" topology --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"topology"* ]]
}

@test "pwt topology -h shows usage" {
    run "$PWT_BIN" topology -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"topology"* ]]
}

# Note: Full topology tests skipped because they use AI
# which is slow and unsuitable for automated testing
