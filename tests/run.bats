#!/usr/bin/env bats
# Tests for pwt run command
# Verifies command execution in worktree context

bats_require_minimum_version 1.5.0
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

    # Create a worktree for tests
    "$PWT_BIN" create WT-RUN HEAD
}

teardown() {
    teardown_test_env
}

# ============================================
# Basic run
# ============================================

@test "pwt run executes command in worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run WT-RUN pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-RUN"* ]]
}

@test "pwt run passes arguments to command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run WT-RUN echo "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello world"* ]]
}

@test "pwt run fails for nonexistent worktree" {
    cd "$TEST_REPO"
    run -127 "$PWT_BIN" run NONEXISTENT pwd
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "pwt run fails without command" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run WT-RUN
    [ "$status" -ne 0 ]
    [[ "$output" == *"No command"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "pwt run without args shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ============================================
# run complex commands
# ============================================

@test "pwt run executes shell commands with pipes" {
    cd "$TEST_REPO"
    # Create a file in worktree
    echo -e "line1\nline2\nline3" > "$TEST_WORKTREES/WT-RUN/test-lines.txt"

    run "$PWT_BIN" run WT-RUN sh -c "cat test-lines.txt | wc -l"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
}

@test "pwt run executes git commands in worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run WT-RUN git branch --show-current
    [ "$status" -eq 0 ]
    [[ "$output" == *"test/WT-RUN"* ]]
}

@test "pwt run preserves command exit status" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run WT-RUN false
    [ "$status" -ne 0 ]
}

# ============================================
# run @ for main app
# ============================================

@test "pwt run @ executes in main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run @ pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]] || [[ "$output" == *"test-repo"* ]]
}

@test "pwt run @ can read files from main app" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run @ cat file.txt
    [ "$status" -eq 0 ]
    [ "$output" = "content" ] || [[ "$output" == *"content"* ]]
}

# ============================================
# run from different contexts
# ============================================

@test "pwt run works from inside worktree" {
    cd "$TEST_WORKTREES/WT-RUN"
    run "$PWT_BIN" run WT-RUN pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-RUN"* ]]
}

@test "pwt run works from unrelated directory" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project run WT-RUN pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-RUN"* ]]
}

# ============================================
# run with project prefix
# ============================================

@test "pwt <project> run works from anywhere" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project run WT-RUN echo "from anywhere"
    [ "$status" -eq 0 ]
    [[ "$output" == *"from anywhere"* ]]
}

# ============================================
# run file operations
# ============================================

@test "pwt run can create files in worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" run WT-RUN touch created-file.txt
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORKTREES/WT-RUN/created-file.txt" ]
}

@test "pwt run can read files from worktree" {
    cd "$TEST_REPO"
    echo "test content" > "$TEST_WORKTREES/WT-RUN/readable.txt"

    run "$PWT_BIN" run WT-RUN cat readable.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"test content"* ]]
}

# ============================================
# run with multiple worktrees
# ============================================

@test "pwt run executes in correct worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-RUN2 HEAD

    # Create different files in each
    echo "wt1" > "$TEST_WORKTREES/WT-RUN/marker.txt"
    echo "wt2" > "$TEST_WORKTREES/WT-RUN2/marker.txt"

    run "$PWT_BIN" run WT-RUN cat marker.txt
    [[ "$output" == *"wt1"* ]]

    run "$PWT_BIN" run WT-RUN2 cat marker.txt
    [[ "$output" == *"wt2"* ]]
}

# ============================================
# run with optional worktree (uses current/main)
# ============================================

@test "pwt run without worktree uses current or main" {
    cd "$TEST_REPO"

    # Clear current symlink to test fallback to main
    rm -f "$PWT_DIR/projects/test-project/current"

    echo "main-marker" > "$TEST_REPO/main-file.txt"

    # When no worktree specified and no current, should use main
    run "$PWT_BIN" run cat main-file.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"main-marker"* ]]
}

@test "pwt run without worktree uses current symlink" {
    cd "$TEST_REPO"

    # Set current to WT-RUN
    "$PWT_BIN" use WT-RUN

    # Create marker in worktree
    echo "current-marker" > "$TEST_WORKTREES/WT-RUN/current-file.txt"

    run "$PWT_BIN" run cat current-file.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"current-marker"* ]]
}

@test "pwt run detects worktree vs command" {
    cd "$TEST_REPO"

    # 'echo' is not a worktree, so it should be treated as command
    run "$PWT_BIN" run echo "test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test"* ]]
}

@test "pwt run with explicit worktree takes precedence" {
    cd "$TEST_REPO"
    "$PWT_BIN" use WT-RUN

    # Even though current is WT-RUN, @ should run in main
    run "$PWT_BIN" run @ pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_REPO"* ]] || [[ "$output" == *"test-repo"* ]]
}
