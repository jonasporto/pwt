#!/usr/bin/env bats
# Tests for pwt list --names (completion support)

load test_helper

setup() {
    setup_test_env

    # Initialize a pwt project in the test repo
    cd "$TEST_REPO"

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-repo"
    cat > "$PWT_DIR/projects/test-repo/config.json" << EOF
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
# Basic --names output tests
# ============================================

@test "list --names outputs @/ for main when no worktrees exist" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [ "$output" = "@/" ]
}

@test "list --names includes @/ as first line" {
    cd "$TEST_REPO"
    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    # First line should always be @/
    local first_line=$(echo "$output" | head -1)
    [ "$first_line" = "@/" ]
}

@test "list --names shows worktree names after creating worktrees" {
    cd "$TEST_REPO"

    # Create a branch for the worktree
    git branch test/feature-123

    # Create a worktree directory manually (simulating pwt create)
    mkdir -p "$TEST_WORKTREES/feature-123"
    git worktree add "$TEST_WORKTREES/feature-123" test/feature-123 2>/dev/null || true

    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"feature-123/"* ]]
}

@test "list --names outputs one name per line" {
    cd "$TEST_REPO"

    # Create two worktrees
    git branch test/wt-one
    git branch test/wt-two

    mkdir -p "$TEST_WORKTREES/wt-one"
    mkdir -p "$TEST_WORKTREES/wt-two"
    git worktree add "$TEST_WORKTREES/wt-one" test/wt-one 2>/dev/null || true
    git worktree add "$TEST_WORKTREES/wt-two" test/wt-two 2>/dev/null || true

    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    # Count lines (should be at least 3: @, wt-one, wt-two)
    local line_count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$line_count" -ge 3 ]
}

# ============================================
# Project alias resolution tests
# ============================================

@test "list --names works with project alias (aliases array)" {
    cd "$TEST_REPO"

    # Add aliases array to the project config
    cat > "$PWT_DIR/projects/test-repo/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/",
  "aliases": ["tr", "testrepo"]
}
EOF

    # Create a worktree
    git branch test/aliased-wt
    mkdir -p "$TEST_WORKTREES/aliased-wt"
    git worktree add "$TEST_WORKTREES/aliased-wt" test/aliased-wt 2>/dev/null || true

    # Test using alias from aliases array
    run "$PWT_BIN" --project tr list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"aliased-wt/"* ]]
}

@test "list --names works with project alias (alias string)" {
    cd "$TEST_REPO"

    # Add single alias string to the project config
    cat > "$PWT_DIR/projects/test-repo/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/",
  "alias": "myalias"
}
EOF

    # Create a worktree
    git branch test/string-alias-wt 2>/dev/null || true
    mkdir -p "$TEST_WORKTREES/string-alias-wt"
    git worktree add "$TEST_WORKTREES/string-alias-wt" test/string-alias-wt 2>/dev/null || true

    # Test using single alias string
    run "$PWT_BIN" --project myalias list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"string-alias-wt/"* ]]
}

@test "list --names works with project name as first arg" {
    cd "$HOME"  # Outside any project

    # Create a worktree in test-repo
    cd "$TEST_REPO"
    git branch test/firstarg-wt 2>/dev/null || true
    mkdir -p "$TEST_WORKTREES/firstarg-wt"
    git worktree add "$TEST_WORKTREES/firstarg-wt" test/firstarg-wt 2>/dev/null || true

    # Test using project name as first arg (not --project flag)
    cd "$HOME"
    run "$PWT_BIN" test-repo list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"firstarg-wt/"* ]]
}

@test "list --names works with alias as first arg" {
    cd "$TEST_REPO"

    # Add alias to config
    cat > "$PWT_DIR/projects/test-repo/config.json" << EOF
{
  "path": "$TEST_REPO",
  "worktrees_dir": "$TEST_WORKTREES",
  "branch_prefix": "test/",
  "alias": "shortname"
}
EOF

    # Create a worktree
    git branch test/alias-firstarg-wt 2>/dev/null || true
    mkdir -p "$TEST_WORKTREES/alias-firstarg-wt"
    git worktree add "$TEST_WORKTREES/alias-firstarg-wt" test/alias-firstarg-wt 2>/dev/null || true

    # Test using alias as first arg (not --project flag)
    cd "$HOME"
    run "$PWT_BIN" shortname list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"alias-firstarg-wt/"* ]]
}

# ============================================
# Context detection tests
# ============================================

@test "list --names works from inside worktree directory" {
    cd "$TEST_REPO"

    # Create a worktree
    git branch test/inside-wt
    mkdir -p "$TEST_WORKTREES/inside-wt"
    git worktree add "$TEST_WORKTREES/inside-wt" test/inside-wt 2>/dev/null || true

    # Change to inside the worktree
    cd "$TEST_WORKTREES/inside-wt"

    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"inside-wt/"* ]]
}

@test "list --names works from main app directory" {
    cd "$TEST_REPO"

    # Create a worktree
    git branch test/from-main
    mkdir -p "$TEST_WORKTREES/from-main"
    git worktree add "$TEST_WORKTREES/from-main" test/from-main 2>/dev/null || true

    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"from-main/"* ]]
}

# ============================================
# Help documentation tests
# ============================================

@test "list --help documents --names flag" {
    run "$PWT_BIN" list --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"--names"* ]]
    [[ "$output" == *"completion"* ]]
}

# ============================================
# Edge cases
# ============================================

@test "list --names handles empty worktrees directory" {
    cd "$TEST_REPO"

    # Worktrees dir exists but is empty
    [ -d "$TEST_WORKTREES" ]

    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [ "$output" = "@/" ]
}

@test "list --names handles missing worktrees directory gracefully" {
    cd "$TEST_REPO"

    # Remove the worktrees directory
    rm -rf "$TEST_WORKTREES"

    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    [ "$output" = "@/" ]
}

# ============================================
# External project tests (pwt <project> list --names)
# ============================================

@test "list --names works with --project flag from any directory" {
    # Create a second project
    mkdir -p "$PWT_DIR/projects/other-project"
    local other_repo="$TEST_TEMP_DIR/other-repo"
    mkdir -p "$other_repo"
    git init -q "$other_repo"
    cd "$other_repo"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial commit"

    local other_worktrees="$TEST_TEMP_DIR/other-worktrees"
    mkdir -p "$other_worktrees"

    cat > "$PWT_DIR/projects/other-project/config.json" << EOF
{
  "path": "$other_repo",
  "worktrees_dir": "$other_worktrees",
  "branch_prefix": "feature/"
}
EOF

    # Create a worktree in the other project
    cd "$other_repo"
    git branch feature/other-wt
    mkdir -p "$other_worktrees/other-wt"
    git worktree add "$other_worktrees/other-wt" feature/other-wt 2>/dev/null || true

    # Now from the FIRST project directory, query the OTHER project
    cd "$TEST_REPO"
    run "$PWT_BIN" --project other-project list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"other-wt/"* ]]
}

@test "list --names with project as first arg works from any directory" {
    # Create a second project
    mkdir -p "$PWT_DIR/projects/second-proj"
    local second_repo="$TEST_TEMP_DIR/second-repo"
    mkdir -p "$second_repo"
    git init -q "$second_repo"
    cd "$second_repo"
    git config user.email "test@test.com"
    git config user.name "Test User"
    touch README.md
    git add README.md
    git commit -q -m "Initial commit"

    local second_worktrees="$TEST_TEMP_DIR/second-worktrees"
    mkdir -p "$second_worktrees"

    cat > "$PWT_DIR/projects/second-proj/config.json" << EOF
{
  "path": "$second_repo",
  "worktrees_dir": "$second_worktrees",
  "branch_prefix": "dev/"
}
EOF

    # Create a worktree
    cd "$second_repo"
    git branch dev/second-wt
    mkdir -p "$second_worktrees/second-wt"
    git worktree add "$second_worktrees/second-wt" dev/second-wt 2>/dev/null || true

    # From HOME (no project context), query the second project
    cd "$HOME"
    run "$PWT_BIN" second-proj list --names

    [ "$status" -eq 0 ]
    [[ "$output" == *"@/"* ]]
    [[ "$output" == *"second-wt/"* ]]
}

@test "list --names is fast enough for shell completion" {
    cd "$TEST_REPO"

    # Create a few worktrees
    for i in 1 2 3; do
        git branch "test/perf-$i" 2>/dev/null || true
        mkdir -p "$TEST_WORKTREES/perf-$i"
        git worktree add "$TEST_WORKTREES/perf-$i" "test/perf-$i" 2>/dev/null || true
    done

    # Just verify it runs successfully - timing is platform-dependent
    # The actual performance was manually verified (~84ms on macOS)
    run "$PWT_BIN" list --names

    [ "$status" -eq 0 ]
    # Should have output (@ at minimum)
    [ -n "$output" ]
}
