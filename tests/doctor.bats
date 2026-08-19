#!/usr/bin/env bats
# Tests for pwt doctor command
# Verifies health check functionality

load test_helper

setup() {
    setup_test_env

    # Create worktrees directory
    export TEST_WORKTREES="$TEST_TEMP_DIR/worktrees"
    mkdir -p "$TEST_WORKTREES"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_WORKTREES
branch_prefix=test/
EOF

    # Add a commit
    cd "$TEST_REPO"
    echo "content" >file.txt
    git add file.txt
    git commit -q -m "Add file"
}

teardown() {
    teardown_test_env
}

# ============================================
# doctor basic
# ============================================

@test "pwt doctor runs successfully" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt doctor"* ]]
}

@test "pwt doctor checks git" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "pwt doctor checks jq" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"jq"* ]]
}

@test "pwt doctor shows project info" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project"* ]] || [[ "$output" == *"test-project"* ]]
}

@test "pwt doctor shows main app path" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Main app"* ]] || [[ "$output" == *"$TEST_REPO"* ]]
}

@test "pwt doctor shows worktrees directory" {
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktrees"* ]] || [[ "$output" == *"worktrees"* ]]
}

# ============================================
# doctor with worktrees
# ============================================

@test "pwt doctor shows worktree count" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DOC1 HEAD
    "$PWT_BIN" create WT-DOC2 HEAD

    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"2"* ]] || [[ "$output" == *"worktree"* ]]
}

# ============================================
# doctor checks Pwtfile
# ============================================

@test "pwt doctor reports Pwtfile when present" {
    cd "$TEST_REPO"
    echo "setup() { echo test; }" >"$TEST_REPO/Pwtfile"

    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pwtfile"* ]]
}

@test "pwt doctor reports Pwtfile not found when absent" {
    cd "$TEST_REPO"
    rm -f "$TEST_REPO/Pwtfile"

    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pwtfile"* ]]
}

# ============================================
# doctor via project prefix
# ============================================

@test "pwt <project> doctor works from anywhere" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"pwt doctor"* ]]
}

# ============================================
# Pwtfile detection + project-defined checks
# Regression: doctor consulted $PWTFILE, a variable never assigned anywhere,
# so a Pwtfile declared in project config (living outside the repo) was
# always reported as "not found".
# ============================================

@test "doctor finds a Pwtfile declared in project config" {
    local ext_dir="$TEST_TEMP_DIR/external"
    mkdir -p "$ext_dir"
    cat >"$ext_dir/Pwtfile" <<'EOF'
server() { echo "srv"; }
EOF
    printf 'pwtfile=%s\n' "$ext_dir/Pwtfile" >>"$PWT_DIR/projects/test-project/config"

    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [[ "$output" == *"Pwtfile: $ext_dir/Pwtfile"* ]]
    [[ "$output" != *"Pwtfile: not found"* ]]
}

@test "doctor flags a Pwtfile declared but missing" {
    printf 'pwtfile=%s\n' "$TEST_TEMP_DIR/nowhere/Pwtfile" >>"$PWT_DIR/projects/test-project/config"

    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [[ "$output" == *"declared but missing"* ]]
}

@test "doctor still reports optional when no Pwtfile exists" {
    rm -f "$TEST_REPO/Pwtfile"
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [[ "$output" == *"Pwtfile: not found (optional)"* ]]
}

@test "doctor runs the Pwtfile doctor() hook when defined" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
doctor() {
    echo "PROJECT_CHECK_RAN"
}
EOF
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project checks"* ]]
    [[ "$output" == *"PROJECT_CHECK_RAN"* ]]
}

@test "doctor skips project checks when the Pwtfile has no doctor()" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
server() { echo "srv"; }
EOF
    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [[ "$output" != *"Project checks"* ]]
}

# Regression: the hook ran in a pipeline, so under `set -e -o pipefail` a
# failing health check aborted doctor - the checks after it never printed.
@test "doctor continues past a Pwtfile doctor() that fails" {
    cat >"$TEST_REPO/Pwtfile" <<'EOF'
doctor() {
    echo "PROJECT_CHECK_RAN"
    command -v definitely_not_installed_xyz123
}
EOF

    cd "$TEST_REPO"
    run "$PWT_BIN" doctor
    [[ "$output" == *"PROJECT_CHECK_RAN"* ]]
    # Everything after the hook must still run
    [[ "$output" == *"All checks passed"* ]] || [[ "$output" == *"issue"* ]]
}

# ============================================
# Installations: which pwt actually answers
# ============================================
# Measured cost of not having this: an hour of debugging fixes that were
# correct all along, because the terminal ran an npm-installed 0.2.8
# while the repo binary carried them. doctor is the command whose job is
# "tell me what is wrong with my setup", and "you are not running the
# pwt you think" is the setup problem that hides every other one.

_second_install() {
    # A genuinely distinct install (copy, not symlink: doctor compares
    # resolved paths, and a symlink would collapse into the original)
    mkdir -p "$TEST_TEMP_DIR/other/bin"
    cp "$PWT_BIN" "$TEST_TEMP_DIR/other/bin/pwt"
    cp -R "$(dirname "$PWT_BIN")/../lib" "$TEST_TEMP_DIR/other/lib"
}

@test "doctor warns when the pwt on PATH is not the one running" {
    _second_install
    cd "$TEST_REPO"
    PATH="$TEST_TEMP_DIR/other/bin:$PATH" run "$PWT_BIN" doctor
    [[ "$output" == *"not the one running"* ]] || {
        echo "expected the shadow warning, got: $output" >&2
        return 1
    }
    [[ "$output" == *"$TEST_TEMP_DIR/other/bin/pwt"* ]] || {
        echo "the warning must name the PATH binary, got: $output" >&2
        return 1
    }
}

@test "doctor lists other installations with their versions" {
    _second_install
    cd "$TEST_REPO"
    PATH="$TEST_TEMP_DIR/other/bin:$PATH" run "$PWT_BIN" doctor
    [[ "$output" == *"pwt self"* ]] || {
        echo "expected the pointer to 'pwt self', got: $output" >&2
        return 1
    }
}

@test "doctor is calm when the running pwt is the one on PATH" {
    cd "$TEST_REPO"
    PATH="$(dirname "$PWT_BIN"):/usr/bin:/bin" run "$PWT_BIN" doctor
    [[ "$output" != *"not the one running"* ]] || {
        echo "no shadow exists, no warning may fire: $output" >&2
        return 1
    }
    [[ "$output" == *"Installation"* ]] || {
        echo "the section must still confirm which install answers: $output" >&2
        return 1
    }
}
