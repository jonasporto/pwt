#!/usr/bin/env bats
# Tests for pwt_arg helper function
# Verifies flag extraction from PWT_ARGS

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
# pwt_arg unit tests (via Pwtfile)
# ============================================

@test "pwt_arg extracts -p value" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local port=$(pwt_arg -p)
    echo "PORT=${port}" > "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG1 HEAD
    cd "$TEST_WORKTREES/TEST-ARG1"
    "$PWT_BIN" mycmd -p 5002

    grep -q "PORT=5002" "$TEST_WORKTREES/TEST-ARG1/.result"
}

@test "pwt_arg extracts --port=value syntax" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local port=$(pwt_arg --port)
    echo "PORT=${port}" > "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG2 HEAD
    cd "$TEST_WORKTREES/TEST-ARG2"
    "$PWT_BIN" mycmd --port=5002

    grep -q "PORT=5002" "$TEST_WORKTREES/TEST-ARG2/.result"
}

@test "pwt_arg returns true for boolean flag" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local sidekiq=$(pwt_arg --sidekiq)
    echo "SIDEKIQ=${sidekiq}" > "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG3 HEAD
    cd "$TEST_WORKTREES/TEST-ARG3"
    "$PWT_BIN" mycmd --sidekiq

    grep -q "SIDEKIQ=true" "$TEST_WORKTREES/TEST-ARG3/.result"
}

@test "pwt_arg returns true for boolean flag followed by another flag" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local sidekiq=$(pwt_arg --sidekiq)
    local env=$(pwt_arg -e)
    echo "SIDEKIQ=${sidekiq}" > "$PWT_WORKTREE_PATH/.result"
    echo "ENV=${env}" >> "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG4 HEAD
    cd "$TEST_WORKTREES/TEST-ARG4"
    "$PWT_BIN" mycmd --sidekiq -e staging

    grep -q "SIDEKIQ=true" "$TEST_WORKTREES/TEST-ARG4/.result"
    grep -q "ENV=staging" "$TEST_WORKTREES/TEST-ARG4/.result"
}

@test "pwt_arg returns empty for missing flag" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local port=$(pwt_arg -p || true)
    echo "PORT=${port}" > "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG5 HEAD
    cd "$TEST_WORKTREES/TEST-ARG5"
    "$PWT_BIN" mycmd --sidekiq

    grep -q "PORT=$" "$TEST_WORKTREES/TEST-ARG5/.result"
}

@test "pwt_arg works with set -u (strict mode)" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
set -u
mycmd() {
    local port=$(pwt_arg -p || true)
    echo "PORT=${port:-none}" > "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG6 HEAD
    cd "$TEST_WORKTREES/TEST-ARG6"
    "$PWT_BIN" mycmd

    grep -q "PORT=none" "$TEST_WORKTREES/TEST-ARG6/.result"
}

@test "pwt_arg coalesce pattern works" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local override_port=$(pwt_arg -p || true)
    local port=${override_port:-$PWT_PORT}
    echo "PORT=${port}" > "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG7 HEAD
    cd "$TEST_WORKTREES/TEST-ARG7"

    # Without override: uses PWT_PORT
    "$PWT_BIN" mycmd
    grep -qE "PORT=[0-9]+" "$TEST_WORKTREES/TEST-ARG7/.result"

    # With override: uses -p value
    "$PWT_BIN" mycmd -p 9999
    grep -q "PORT=9999" "$TEST_WORKTREES/TEST-ARG7/.result"
}

@test "pwt_arg extracts from multiple mixed flags" {
    cd "$TEST_REPO"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
mycmd() {
    local port=$(pwt_arg -p || true)
    local env=$(pwt_arg -e || true)
    local verbose=$(pwt_arg --verbose || true)
    echo "PORT=${port}" > "$PWT_WORKTREE_PATH/.result"
    echo "ENV=${env}" >> "$PWT_WORKTREE_PATH/.result"
    echo "VERBOSE=${verbose}" >> "$PWT_WORKTREE_PATH/.result"
}
PWTEOF

    "$PWT_BIN" create TEST-ARG8 HEAD
    cd "$TEST_WORKTREES/TEST-ARG8"
    "$PWT_BIN" mycmd --verbose -p 5002 -e staging

    grep -q "PORT=5002" "$TEST_WORKTREES/TEST-ARG8/.result"
    grep -q "ENV=staging" "$TEST_WORKTREES/TEST-ARG8/.result"
    grep -q "VERBOSE=true" "$TEST_WORKTREES/TEST-ARG8/.result"
}
