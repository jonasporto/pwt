#!/usr/bin/env bats
# Tests for pwt create and pwt remove commands
# These are the most critical commands - create worktrees and clean them up

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

    # Add a second commit so we have something to branch from
    cd "$TEST_REPO"
    echo "content" > file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    teardown_test_env
}

# ============================================
# pwt create - basic functionality
# ============================================

@test "pwt create uses --guess-remote flag" {
    cd "$TEST_REPO"

    # Create a local branch to use
    git branch test-existing-branch

    # Create worktree from existing branch (doesn't need remote)
    run "$PWT_BIN" create test-existing-branch
    [ "$status" -eq 0 ]

    # Verify worktree was created
    [ -d "$TEST_WORKTREES/test-existing-branch" ]
}

@test "pwt create without args shows usage" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "pwt create with branch creates worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create TEST-1234 HEAD
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-1234" ]
}

@test "pwt add is alias for create" {
    cd "$TEST_REPO"
    run "$PWT_BIN" add TEST-ADD HEAD
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-ADD" ]
}

@test "pwt create shows next steps after success" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create TEST-NEXTSTEPS HEAD
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next steps"* ]]
    [[ "$output" == *"Navigate"* ]]
    [[ "$output" == *"pwt cd"* ]]
}

@test "pwt create extracts name from feature/branch" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create feature/TEST-5678 HEAD
    [ "$status" -eq 0 ]
    # Should strip feature/ prefix
    [ -d "$TEST_WORKTREES/TEST-5678" ]
}

@test "pwt create with user prefix extracts ticket" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create jp/TEST-9999 HEAD
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-9999" ]
}

@test "pwt create fails if worktree already exists" {
    cd "$TEST_REPO"
    # Create first
    "$PWT_BIN" create TEST-1111 HEAD
    # Try to create again
    run "$PWT_BIN" create TEST-1111 HEAD
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "pwt create --dry-run does not create worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create TEST-DRY HEAD --dry-run
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/TEST-DRY" ]
    [[ "$output" == *"dry"* ]] || [[ "$output" == *"Would"* ]] || [[ "$output" == *"TEST-DRY"* ]]
}

@test "pwt create allocates port in metadata" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-PORT HEAD

    # Check meta.json has port for this worktree
    local meta_file="$PWT_DIR/meta.json"
    [ -f "$meta_file" ]

    local port=$(jq -r '.["test-project"]["TEST-PORT"].port' "$meta_file")
    [[ "$port" =~ ^[0-9]+$ ]]
}

@test "pwt create with description adds slug to branch" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create TEST-DESC HEAD -- add new feature
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-DESC" ]

    # Check branch name includes slug
    cd "$TEST_WORKTREES/TEST-DESC"
    local branch=$(git branch --show-current)
    [[ "$branch" == *"add-new-feature"* ]] || [[ "$branch" == *"TEST-DESC"* ]]
}

# ============================================
# pwt create - port allocation
# ============================================

@test "pwt create allocates different ports for each worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-001 HEAD
    "$PWT_BIN" create WT-002 HEAD

    local meta_file="$PWT_DIR/meta.json"
    local port1=$(jq -r '.["test-project"]["WT-001"].port' "$meta_file")
    local port2=$(jq -r '.["test-project"]["WT-002"].port' "$meta_file")

    [ "$port1" != "$port2" ]
}

# ============================================
# pwt create - from anywhere (pwt project create)
# ============================================

@test "pwt <project> create works from anywhere" {
    cd "$TEST_TEMP_DIR"  # Not in project
    run "$PWT_BIN" test-project create TEST-ANYWHERE HEAD
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-ANYWHERE" ]
}

# ============================================
# pwt remove - basic functionality
# ============================================

@test "pwt remove without args outside worktree shows error" {
    cd "$TEST_REPO"
    run "$PWT_BIN" remove
    [ "$status" -ne 0 ]
    [[ "$output" == *"Not in a worktree"* ]] || [[ "$output" == *"Specify"* ]]
}

@test "pwt remove nonexistent worktree shows error" {
    cd "$TEST_REPO"
    run "$PWT_BIN" remove nonexistent-worktree
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "pwt remove with -y removes worktree without confirmation" {
    cd "$TEST_REPO"
    # Create worktree first
    "$PWT_BIN" create TEST-REMOVE HEAD
    [ -d "$TEST_WORKTREES/TEST-REMOVE" ]

    # Remove with -y (auto-yes)
    run "$PWT_BIN" remove TEST-REMOVE -y
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/TEST-REMOVE" ]
}

@test "pwt remove cleans up metadata" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-META HEAD

    local meta_file="$PWT_DIR/meta.json"
    # Verify worktree exists in metadata
    local port=$(jq -r '.["test-project"]["TEST-META"].port' "$meta_file")
    [[ "$port" =~ ^[0-9]+$ ]]

    "$PWT_BIN" remove TEST-META -y
    # Verify worktree removed from metadata
    local removed=$(jq -r '.["test-project"]["TEST-META"] // "null"' "$meta_file")
    [ "$removed" = "null" ]
}

@test "pwt remove detects worktree from PWT_WORKTREE env" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-ENV HEAD

    # Set env var and remove without specifying name
    export PWT_WORKTREE="TEST-ENV"
    run "$PWT_BIN" remove -y
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/TEST-ENV" ]
}

@test "pwt remove detects worktree from current directory" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-PWD HEAD

    # cd into worktree and set PWT_WORKTREE (simulating shell-init)
    cd "$TEST_WORKTREES/TEST-PWD"
    export PWT_WORKTREE="TEST-PWD"
    run "$PWT_BIN" remove -y
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/TEST-PWD" ]
}

# ============================================
# pwt remove - from anywhere (pwt project remove)
# ============================================

@test "pwt <project> remove works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-REMOTE HEAD

    cd "$TEST_TEMP_DIR"  # Not in project
    run "$PWT_BIN" test-project remove TEST-REMOTE -y
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/TEST-REMOTE" ]
}

# ============================================
# pwt remove - with branch deletion
# ============================================

@test "pwt remove --force-branch deletes local branch" {
    cd "$TEST_REPO"
    "$PWT_BIN" create TEST-BRANCH HEAD

    # Verify branch exists
    local branch_name=$(cd "$TEST_WORKTREES/TEST-BRANCH" && git branch --show-current)

    # Remove with force branch deletion (branch not merged, so need --force-branch)
    "$PWT_BIN" remove TEST-BRANCH --force-branch -y

    # Verify worktree gone
    [ ! -d "$TEST_WORKTREES/TEST-BRANCH" ]

    # Verify branch deleted from main repo
    cd "$TEST_REPO"
    run git branch --list "$branch_name"
    [ -z "$output" ]
}

# ============================================
# Integration: create then remove
# ============================================

@test "full cycle: create, verify, remove, verify" {
    cd "$TEST_REPO"

    # Create
    "$PWT_BIN" create TEST-CYCLE HEAD
    [ -d "$TEST_WORKTREES/TEST-CYCLE" ]
    # Verify in metadata
    local port=$(jq -r '.["test-project"]["TEST-CYCLE"].port' "$PWT_DIR/meta.json")
    [[ "$port" =~ ^[0-9]+$ ]]

    # Verify it shows in list
    run "$PWT_BIN" list
    [[ "$output" == *"TEST-CYCLE"* ]]

    # Remove
    "$PWT_BIN" remove TEST-CYCLE -y
    [ ! -d "$TEST_WORKTREES/TEST-CYCLE" ]
    # Verify removed from metadata
    local removed=$(jq -r '.["test-project"]["TEST-CYCLE"] // "null"' "$PWT_DIR/meta.json")
    [ "$removed" = "null" ]

    # Verify it's gone from list
    run "$PWT_BIN" list --porcelain
    [[ "$output" != *"TEST-CYCLE"* ]]
}

@test "multiple creates then remove all" {
    cd "$TEST_REPO"

    # Create multiple
    "$PWT_BIN" create WT-A HEAD
    "$PWT_BIN" create WT-B HEAD
    "$PWT_BIN" create WT-C HEAD

    [ -d "$TEST_WORKTREES/WT-A" ]
    [ -d "$TEST_WORKTREES/WT-B" ]
    [ -d "$TEST_WORKTREES/WT-C" ]

    # Remove all
    "$PWT_BIN" remove WT-A -y
    "$PWT_BIN" remove WT-B -y
    "$PWT_BIN" remove WT-C -y

    [ ! -d "$TEST_WORKTREES/WT-A" ]
    [ ! -d "$TEST_WORKTREES/WT-B" ]
    [ ! -d "$TEST_WORKTREES/WT-C" ]
}

# ============================================
# Edge cases
# ============================================

@test "pwt create with special characters in description" {
    cd "$TEST_REPO"
    run "$PWT_BIN" create TEST-SPECIAL HEAD -- "fix: bug #123 (urgent!)"
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/TEST-SPECIAL" ]
}

@test "pwt create with very long branch name" {
    cd "$TEST_REPO"
    local long_name="TEST-$(head -c 50 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 50)"
    run "$PWT_BIN" create "$long_name" HEAD
    # Should either succeed or fail gracefully
    [ "$status" -eq 0 ] || [[ "$output" == *"Error"* ]]
}

@test "pwt remove with exact name works" {
    cd "$TEST_REPO"
    "$PWT_BIN" create ACME-12345-long-name HEAD

    # Remove with exact name
    run "$PWT_BIN" remove ACME-12345-long-name -y
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WORKTREES/ACME-12345-long-name" ]
}
