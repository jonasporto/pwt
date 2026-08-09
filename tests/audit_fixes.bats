#!/usr/bin/env bats
# Regression tests for audit fixes
# and the codebase-gateway features (post_use hook, editor --pinned,
# workspace_link, adopt --all).

load test_helper

setup() {
    setup_test_env

    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Randomized base_port: TCP ports are machine-global, so a real server
    # started here on the default 5001 collides with port checks in other
    # test files running in parallel (same pattern as gateway.bats)
    export TEST_BASE_PORT=$((43000 + RANDOM % 1000))
    mkdir -p "$PWT_DIR/projects/test-project"
    cat > "$PWT_DIR/projects/test-project/config" << EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
base_port=$TEST_BASE_PORT
EOF
    cd "$TEST_REPO"
    git branch -m main 2>/dev/null || true
}

teardown() {
    teardown_test_env
}

# ============================================
# A1: create in a repo without a remote
# ============================================

@test "create with base main works without a remote (falls back to local)" {
    run "$PWT_BIN" create NOREMOTE-1 main "no remote"
    [ "$status" -eq 0 ]
    [[ "$output" == *"using local main"* ]]
    [ -d "$TEST_WORKTREES/NOREMOTE-1" ]
}

@test "create --from main works without a remote" {
    run "$PWT_BIN" create NOREMOTE-2 --from main
    [ "$status" -eq 0 ]
    [ -d "$TEST_WORKTREES/NOREMOTE-2" ]
}

@test "create with explicit origin/* base fails clearly without a remote" {
    run "$PWT_BIN" create NOREMOTE-3 origin/main
    [ "$status" -ne 0 ]
    [[ "$output" == *"Remote ref not found"* ]]
}

# ============================================
# A2: copy with path patterns, Git metadata pruned
# ============================================

@test "copy matches path patterns like src/*.js" {
    "$PWT_BIN" create CP-SRC HEAD
    "$PWT_BIN" create CP-DST HEAD
    mkdir -p "$TEST_WORKTREES/CP-SRC/src"
    echo "x" > "$TEST_WORKTREES/CP-SRC/src/index.js"

    run "$PWT_BIN" copy CP-SRC CP-DST "src/*.js"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/index.js"* ]]
    [ -f "$TEST_WORKTREES/CP-DST/src/index.js" ]
}

@test "copy never copies Git metadata" {
    "$PWT_BIN" create CP-GIT-SRC HEAD
    "$PWT_BIN" create CP-GIT-DST HEAD
    mkdir -p "$TEST_WORKTREES/CP-GIT-SRC/nested/.git"
    echo "x" > "$TEST_WORKTREES/CP-GIT-SRC/nested/.git/metadata.js"
    echo "y" > "$TEST_WORKTREES/CP-GIT-SRC/app.js"

    run "$PWT_BIN" copy CP-GIT-SRC CP-GIT-DST "*.js"
    [ "$status" -eq 0 ]
    [ -f "$TEST_WORKTREES/CP-GIT-DST/app.js" ]
    [ ! -f "$TEST_WORKTREES/CP-GIT-DST/nested/.git/metadata.js" ]
}

# ============================================
# A5: run refuses a typo'd worktree name
# ============================================

@test "run with nonexistent worktree (not a command) errors instead of running in main" {
    run "$PWT_BIN" run TYPO-WORKTREE-NAME ls
    [ "$status" -eq 3 ]
    [[ "$output" == *"Worktree not found"* ]]
}

@test "run with a real command as first arg still works" {
    run "$PWT_BIN" run ls
    [ "$status" -eq 0 ]
}

# ============================================
# A6: status was retired (the bash TUI moved to the pwt-ui project)
# ============================================

@test "status exits cleanly with a pointer to the replacements" {
    run "$PWT_BIN" status
    [ "$status" -eq 1 ]
    [[ "$output" == *"pwt status was removed"* ]]
    # No alt-screen escape leak
    [[ "$output" != *$'\033[?1049h'* ]]
}

# ============================================
# A8: removing the current worktree falls back
# ============================================

@test "removing current worktree falls back to previous" {
    "$PWT_BIN" create CUR-A HEAD
    "$PWT_BIN" create CUR-B HEAD
    "$PWT_BIN" use CUR-A
    "$PWT_BIN" use CUR-B

    run "$PWT_BIN" remove CUR-B -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"current → CUR-A"* ]]
    [ -L "$PWT_DIR/projects/test-project/current" ]
    # Compare physical paths (mktemp dirs go through /var -> /private/var on macOS)
    [ "$(cd "$PWT_DIR/projects/test-project/current" && pwd -P)" = "$(cd "$TEST_WORKTREES/CUR-A" && pwd -P)" ]
}

# ============================================
# C2: info --porcelain
# ============================================

@test "info --porcelain emits valid JSON with expected fields" {
    "$PWT_BIN" create INFO-JSON HEAD
    run "$PWT_BIN" info INFO-JSON --porcelain
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.name == "INFO-JSON"'
    echo "$output" | jq -e '.path | test("INFO-JSON")'
    echo "$output" | jq -e '.server == "stopped"'
    echo "$output" | jq -e '.port | type == "number"'
}

@test "project index ignores empty worktrees_dir when detecting project" {
    mkdir -p "$TEST_TEMP_DIR/partial-main"
    mkdir -p "$PWT_DIR/projects/partial-project"
    cat > "$PWT_DIR/projects/partial-project/config" << EOF
path=$TEST_TEMP_DIR/partial-main
EOF

    cd "$HOME"
    run "$PWT_BIN" list --porcelain
    [ "$status" -ne 0 ]
    [[ "$output" == *"No project detected"* ]]
    [[ "$output" != *"Could not determine project paths"* ]]
}

# ============================================
# post_use hook (codebase gateway)
# ============================================

@test "use runs Pwtfile post_use hook with PWT_WORKTREE set" {
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
post_use() {
    echo "POST_USE:$PWT_WORKTREE"
}
EOF
    "$PWT_BIN" create HOOK-1 HEAD
    run "$PWT_BIN" use HOOK-1
    [ "$status" -eq 0 ]
    [[ "$output" == *"POST_USE:HOOK-1"* ]]
}

@test "use @ also runs post_use hook" {
    cat > "$TEST_REPO/Pwtfile" << 'EOF'
post_use() {
    echo "POST_USE:$PWT_WORKTREE"
}
EOF
    "$PWT_BIN" create HOOK-2 HEAD
    run "$PWT_BIN" use @
    [ "$status" -eq 0 ]
    [[ "$output" == *"POST_USE:@"* ]]
}

# ============================================
# editor --pinned (codebase gateway)
# ============================================

@test "editor --pinned opens the stable current symlink" {
    "$PWT_BIN" create PIN-1 HEAD
    EDITOR=echo run "$PWT_BIN" editor --pinned PIN-1
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PWT_DIR/projects/test-project/current"* ]]
    [ "$(readlink "$PWT_DIR/projects/test-project/current")" = "$TEST_WORKTREES/PIN-1" ]
}

@test "editor --pinned without current symlink errors with hint" {
    rm -f "$PWT_DIR/projects/test-project/current"
    EDITOR=echo run "$PWT_BIN" editor --pinned
    [ "$status" -ne 0 ]
    [[ "$output" == *"No current worktree set"* ]]
}

# ============================================
# workspace_link (codebase gateway)
# ============================================

@test "workspace_link symlink follows pwt use" {
    "$PWT_BIN" create WSL-1 HEAD
    "$PWT_BIN" config workspace_link "$TEST_TEMP_DIR/myapp-code"

    "$PWT_BIN" use WSL-1
    [ "$(readlink "$TEST_TEMP_DIR/myapp-code")" = "$TEST_WORKTREES/WSL-1" ]

    "$PWT_BIN" use @
    [ "$(readlink "$TEST_TEMP_DIR/myapp-code")" = "$TEST_REPO" ]
}

# ============================================
# adopt --all
# ============================================

@test "adopt --all registers unregistered worktrees and skips known ones" {
    "$PWT_BIN" create ADOPTED-1 HEAD
    cd "$TEST_REPO"
    git worktree add "$TEST_WORKTREES/RAW-1" -b raw-1 --quiet
    git worktree add "$TEST_WORKTREES/RAW-2" -b raw-2 --quiet

    run "$PWT_BIN" adopt --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Adopted: 2"* ]]
    [[ "$output" == *"Skipped (already registered): 1"* ]]

    run "$PWT_BIN" list --porcelain
    echo "$output" | jq -e '.worktrees | map(.name) | index("RAW-1") != null'
    echo "$output" | jq -e '.worktrees | map(.name) | index("RAW-2") != null'
}

# ============================================
# Friction round (2026-06-11): --count, ignored-flags warning, Pwtfile help
# ============================================

@test "custom command --bg --count N spawns N registered jobs" {
    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
worker() {
    echo "worker $PWT_JOB_INDEX up"
    sleep 30
}
PWTEOF
    "$PWT_BIN" create COUNT-1 HEAD
    cd "$TEST_WORKTREES/COUNT-1"

    run "$PWT_BIN" worker --bg --count 2
    [ "$status" -eq 0 ]
    local n
    n=$(echo "$output" | grep -c '"job_id"')
    [ "$n" -eq 2 ]

    run "$PWT_BIN" jobs list
    [[ "$output" == *"-1 "* ]]
    [[ "$output" == *"-2 "* ]]

    "$PWT_BIN" jobs stop --all 2>/dev/null || true
}

@test "server already running warns about ignored flags" {
    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
server() {
    sleep 30
}
PWTEOF
    "$PWT_BIN" create DUP-1 HEAD
    cd "$TEST_WORKTREES/DUP-1"
    "$PWT_BIN" server --bg
    run "$PWT_BIN" server --bg --worker
    [ "$status" -ne 0 ]
    [[ "$output" == *"Flags IGNORED: --worker"* ]]
    [[ "$output" == *"jobs stop"* ]]
    "$PWT_BIN" jobs stop --all 2>/dev/null || true
}

@test "server --help shows Pwtfile flag docs" {
    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
# Usage: pwt server [--fancy]
#   --fancy   Enables fancy mode
server() {
    sleep 1
}
PWTEOF
    run "$PWT_BIN" server --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project flags (from Pwtfile server())"* ]]
    [[ "$output" == *"--fancy   Enables fancy mode"* ]]
}

@test "gateway use mentions default flags when auto-starting" {
    # Needs node (gateway daemon) and python3 (the fixture server below);
    # without the guard this hard-fails on minimal boxes instead of skipping
    command -v node >/dev/null 2>&1 || skip "node is required for gateway tests"
    command -v python3 >/dev/null 2>&1 || skip "python3 is required for this fixture server"

    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
server() {
    exec python3 -m http.server "$PWT_PORT"
}
PWTEOF
    "$PWT_BIN" create GWMSG-1 HEAD
    "$PWT_BIN" gateway init --port 39888
    run "$PWT_BIN" gateway use GWMSG-1
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEFAULT flags"* ]]
    "$PWT_BIN" gateway down 2>/dev/null || true
    "$PWT_BIN" jobs stop --all 2>/dev/null || true
}

@test "pwt self lists installations and marks structure" {
    run "$PWT_BIN" self
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt installations"* ]]
    [[ "$output" == *"local"* ]]
}

@test "pwt versions is an alias for self" {
    run "$PWT_BIN" versions
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt installations"* ]]
}

# ============================================
# Worktree-first dispatch + pwt logs (2026-06-12)
# ============================================

@test "pwt <worktree> -- runs command in that worktree" {
    "$PWT_BIN" create WTFIRST-1 HEAD
    cd "$TEST_REPO"
    run "$PWT_BIN" WTFIRST-1 -- pwd
    [ "$status" -eq 0 ]
    [[ "$output" == *"WTFIRST-1"* ]]
}

@test "pwt <worktree> info works (swap dispatch)" {
    "$PWT_BIN" create WTFIRST-2 HEAD
    cd "$TEST_REPO"
    run "$PWT_BIN" WTFIRST-2 info
    [ "$status" -eq 0 ]
    [[ "$output" == *"WTFIRST-2"* ]]
}

@test "pwt logs picks the worktree server job without a job id" {
    cat > "$TEST_REPO/Pwtfile" << 'PWTEOF'
server() {
    echo "SERVER_LOG_LINE"
    sleep 30
}
PWTEOF
    "$PWT_BIN" create LOGS-1 HEAD
    cd "$TEST_WORKTREES/LOGS-1"
    "$PWT_BIN" server --bg
    wait_for "grep -q SERVER_LOG_LINE \"$PWT_DIR\"/jobs/LOGS-1-server-*.log" 3

    run "$PWT_BIN" logs LOGS-1
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_LOG_LINE"* ]]

    # worktree-first form too
    cd "$TEST_REPO"
    run "$PWT_BIN" LOGS-1 logs
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVER_LOG_LINE"* ]]

    "$PWT_BIN" jobs stop --all 2>/dev/null || true
}

@test "pwt logs errors helpfully with no jobs" {
    "$PWT_BIN" create LOGS-2 HEAD
    run "$PWT_BIN" logs LOGS-2
    [ "$status" -ne 0 ]
    [[ "$output" == *"No jobs found"* ]]
    [[ "$output" == *"pwt server LOGS-2 --bg"* ]]
}

# ============================================
# Review fixes (2026-08): implicit-cd flag guard, corrupted config
# tolerance, self-use symlink loop guard
# ============================================

@test "implicit cd rejects flags (never hijacks pwt --version)" {
    cd "$TEST_REPO"
    run "$PWT_BIN" _implicit-cd --version
    [ "$status" -ne 0 ]
    run "$PWT_BIN" _implicit-cd -q
    [ "$status" -ne 0 ]
}

@test "implicit cd still resolves bare - to previous worktree" {
    cd "$TEST_REPO"
    "$PWT_BIN" create IMPL-PREV-1 HEAD
    "$PWT_BIN" create IMPL-PREV-2 HEAD
    "$PWT_BIN" use IMPL-PREV-1
    "$PWT_BIN" use IMPL-PREV-2
    run "$PWT_BIN" _implicit-cd -
    [ "$status" -eq 0 ]
    [[ "$output" == *"IMPL-PREV-1"* ]]
}

@test "unreadable sibling config does not break project resolution" {
    mkdir -p "$PWT_DIR/projects/broken-project"
    echo 'garbage without equals' > "$PWT_DIR/projects/broken-project/config"
    rm -f "$PWT_DIR/cache/project-index"

    cd "$HOME"
    run "$PWT_BIN" test-project list --names
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unknown command"* ]]
}

@test "self use local through the managed symlink does not create a loop" {
    "$PWT_BIN" self use local
    local link="$HOME/.local/bin/pwt"
    [ -L "$link" ]

    # Run 'self use local' THROUGH the symlink it manages: before the fix
    # this produced a self-referential link and every pwt call died with
    # "too many levels of symbolic links"
    run "$link" self use local
    [ "$status" -eq 0 ]
    run "$link" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt version"* ]]
}
