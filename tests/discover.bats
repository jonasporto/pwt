#!/usr/bin/env bats
# Tests for pwt discover command
# Verifies repository discovery and auto-configuration

load test_helper

setup() {
    setup_test_env

    # Create a directory structure with multiple repos
    export PROJECTS_DIR="$TEST_TEMP_DIR/projects"
    mkdir -p "$PROJECTS_DIR"
}

teardown() {
    teardown_test_env
}

# Helper to create a git repo
create_repo() {
    local path="$1"
    local remote="${2:-}"
    mkdir -p "$path"
    git init -q "$path"
    cd "$path"
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "content" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    if [ -n "$remote" ]; then
        git remote add origin "$remote"
    fi
    cd - > /dev/null
}

# ============================================
# Basic discovery - single repo
# ============================================

@test "pwt discover finds single unconfigured repo" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found 1 unconfigured repository"* ]]
    [[ "$output" == *"repo1"* ]]
}

@test "pwt discover shows remote URL" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git@github.com:user/repo1.git"* ]]
}

@test "pwt discover shows branch name" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    # Should show master or main depending on git version
    [[ "$output" == *"(master)"* ]] || [[ "$output" == *"(main)"* ]]
}

@test "pwt discover handles repo without remote" {
    create_repo "$PROJECTS_DIR/repo1"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(no remote)"* ]]
}

# ============================================
# Basic discovery - multiple repos
# ============================================

@test "pwt discover finds two unconfigured repos" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"
    create_repo "$PROJECTS_DIR/repo2" "git@github.com:user/repo2.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found 2 unconfigured repositories"* ]]
    [[ "$output" == *"repo1"* ]]
    [[ "$output" == *"repo2"* ]]
}

@test "pwt discover finds nested repos" {
    create_repo "$PROJECTS_DIR/dir1/repo1" "git@github.com:user/repo1.git"
    create_repo "$PROJECTS_DIR/dir2/nested/repo2" "git@github.com:user/repo2.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found 2"* ]]
    [[ "$output" == *"dir1/repo1"* ]]
    [[ "$output" == *"dir2/nested/repo2"* ]]
}

# ============================================
# Skip configured repos
# ============================================

@test "pwt discover skips already configured repos" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"
    create_repo "$PROJECTS_DIR/repo2" "git@github.com:user/repo2.git"

    # Configure repo1
    cd "$PROJECTS_DIR/repo1"
    "$PWT_BIN" init

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found 1 unconfigured"* ]]
    [[ "$output" == *"repo2"* ]]
    [[ "$output" == *"Skipped (configured)"* ]]
    [[ "$output" == *"repo1"* ]]
}

@test "pwt discover shows no results when all configured" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"

    cd "$PROJECTS_DIR/repo1"
    "$PWT_BIN" init

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No unconfigured repositories found"* ]]
    # Shows the configured repo name in the output
    [[ "$output" == *"repo1"* ]]
}

# ============================================
# --init flag
# ============================================

@test "pwt discover --init configures found repos" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR" --init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Configuring"* ]]
    [[ "$output" == *"Configured: repo1"* ]] || [[ "$output" == *"✓"* ]]

    # Should now be configured
    [ -f "$PWT_DIR/projects/repo1/config.json" ]
}

@test "pwt discover --init configures multiple repos" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"
    create_repo "$PROJECTS_DIR/repo2" "git@github.com:user/repo2.git"

    run "$PWT_BIN" discover "$PROJECTS_DIR" --init
    [ "$status" -eq 0 ]

    [ -f "$PWT_DIR/projects/repo1/config.json" ]
    [ -f "$PWT_DIR/projects/repo2/config.json" ]
}

@test "pwt init --discover works as alias" {
    create_repo "$PROJECTS_DIR/repo1" "git@github.com:user/repo1.git"

    run "$PWT_BIN" init --discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo1"* ]]
}

# ============================================
# Worktrees - should be skipped
# ============================================

@test "pwt discover skips *-worktrees directories" {
    create_repo "$PROJECTS_DIR/myapp" "git@github.com:user/myapp.git"

    # Simulate worktrees directory with a repo inside
    mkdir -p "$PROJECTS_DIR/myapp-worktrees/feature-1"
    git init -q "$PROJECTS_DIR/myapp-worktrees/feature-1"
    cd "$PROJECTS_DIR/myapp-worktrees/feature-1"
    git config user.email "test@test.com"
    git config user.name "Test User"

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found 1 unconfigured"* ]]
    [[ "$output" == *"myapp"* ]]
    [[ "$output" == *"Skipped (worktrees)"* ]] || [[ "$output" != *"feature-1"* ]]
}

@test "pwt discover skips git worktrees (gitdir file)" {
    create_repo "$PROJECTS_DIR/main-repo" "git@github.com:user/main.git"

    # Create an actual git worktree
    cd "$PROJECTS_DIR/main-repo"
    git worktree add "$PROJECTS_DIR/worktree-branch" -b worktree-branch 2>/dev/null || true

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    # Should only find main-repo, not the worktree
    [[ "$output" == *"Found 1 unconfigured"* ]]
    [[ "$output" == *"main-repo"* ]]
}

# ============================================
# Submodules
# ============================================

@test "pwt discover skips submodules by default" {
    # Create parent repo
    create_repo "$PROJECTS_DIR/parent" "git@github.com:user/parent.git"

    # Manually create a submodule-like structure
    # (simulating what git submodule add would create)
    cd "$PROJECTS_DIR/parent"
    mkdir -p vendor/sub

    # Create .gitmodules file
    cat > .gitmodules << 'EOF'
[submodule "vendor/sub"]
    path = vendor/sub
    url = git@github.com:user/sub.git
EOF

    # Create the submodule repo with .git as a file (gitdir reference)
    git init -q vendor/sub
    cd vendor/sub
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "sub content" > README.md
    git add README.md
    git commit -q -m "Initial"

    # Convert .git directory to gitdir file (simulating submodule)
    local git_dir="$PROJECTS_DIR/parent/.git/modules/vendor/sub"
    mkdir -p "$git_dir"
    mv .git/* "$git_dir/" 2>/dev/null || true
    rm -rf .git
    echo "gitdir: $git_dir" > .git

    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    # Should only find parent, not the submodule
    [[ "$output" == *"Found 1 unconfigured"* ]]
    [[ "$output" == *"parent"* ]]
}

@test "pwt discover --include-submodules includes submodules" {
    # Create parent repo
    create_repo "$PROJECTS_DIR/parent" "git@github.com:user/parent.git"

    # Manually create a submodule-like structure
    cd "$PROJECTS_DIR/parent"
    mkdir -p vendor/sub

    # Create .gitmodules file
    cat > .gitmodules << 'EOF'
[submodule "vendor/sub"]
    path = vendor/sub
    url = git@github.com:user/sub.git
EOF

    # Create the submodule repo with .git as a file (gitdir reference)
    git init -q vendor/sub
    cd vendor/sub
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "sub content" > README.md
    git add README.md
    git commit -q -m "Initial"

    # Convert .git directory to gitdir file (simulating submodule)
    local git_dir="$PROJECTS_DIR/parent/.git/modules/vendor/sub"
    mkdir -p "$git_dir"
    mv .git/* "$git_dir/" 2>/dev/null || true
    rm -rf .git
    echo "gitdir: $git_dir" > .git

    run "$PWT_BIN" discover "$PROJECTS_DIR" --include-submodules
    [ "$status" -eq 0 ]
    # Should find both parent and submodule
    [[ "$output" == *"Found 2 unconfigured"* ]]
    [[ "$output" == *"parent"* ]]
    [[ "$output" == *"vendor/sub"* ]]
}

# ============================================
# Depth limit
# ============================================

@test "pwt discover respects --depth flag" {
    # Create deeply nested repo
    create_repo "$PROJECTS_DIR/level1/level2/level3/level4/deep-repo"

    # With default depth (5), should find it
    run "$PWT_BIN" discover "$PROJECTS_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deep-repo"* ]]

    # With depth 2, should not find it
    run "$PWT_BIN" discover "$PROJECTS_DIR" --depth 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"No unconfigured repositories found"* ]] || [[ "$output" != *"deep-repo"* ]]
}

# ============================================
# Edge cases
# ============================================

@test "pwt discover fails on non-existent directory" {
    run "$PWT_BIN" discover "/nonexistent/path"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Directory not found"* ]] || [[ "$output" == *"Error"* ]]
}

@test "pwt discover works with current directory (.)" {
    create_repo "$PROJECTS_DIR/repo1"
    cd "$PROJECTS_DIR"

    run "$PWT_BIN" discover .
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo1"* ]]
}

@test "pwt discover with empty directory shows no results" {
    mkdir -p "$PROJECTS_DIR/empty"

    run "$PWT_BIN" discover "$PROJECTS_DIR/empty"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No unconfigured repositories found"* ]]
}
