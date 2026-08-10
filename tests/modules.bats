#!/usr/bin/env bats
# Tests for pwt module system

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================
# Module files exist
# ============================================

@test "all module files exist" {
    [ -f "$PWT_LIB_DIR/list.sh" ]
    [ -f "$PWT_LIB_DIR/worktree.sh" ]
    [ -f "$PWT_LIB_DIR/project.sh" ]
    [ -f "$PWT_LIB_DIR/plugin.sh" ]
}

@test "all modules have source guards" {
    for module in list worktree project plugin; do
        run grep "_PWT_.*_LOADED" "$PWT_LIB_DIR/${module}.sh"
        [ "$status" -eq 0 ]
    done
}

@test "all modules have valid bash syntax" {
    for module in list worktree project plugin; do
        run bash -n "$PWT_LIB_DIR/${module}.sh"
        [ "$status" -eq 0 ]
    done
}

# ============================================
# load_module function
# ============================================

@test "load_module function exists in main script" {
    run grep "^load_module()" "$PWT_BIN"
    [ "$status" -eq 0 ]
}

@test "main script loads modules on demand" {
    # Check that modules are loaded via load_module
    run grep 'load_module list' "$PWT_BIN"
    [ "$status" -eq 0 ]

    run grep 'load_module worktree' "$PWT_BIN"
    [ "$status" -eq 0 ]

    run grep 'load_module project' "$PWT_BIN"
    [ "$status" -eq 0 ]

    run grep 'load_module plugin' "$PWT_BIN"
    [ "$status" -eq 0 ]
}

# ============================================
# Module commands work
# ============================================

@test "list command works (loads list module)" {
    cd "$TEST_REPO"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_TEMP_DIR/worktrees
branch_prefix=test/
EOF

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
}

@test "tree command works (loads list module)" {
    cd "$TEST_REPO"

    # Create project config
    mkdir -p "$PWT_DIR/projects/test-project"
    cat >"$PWT_DIR/projects/test-project/config" <<EOF
path=$TEST_REPO
worktrees_dir=$TEST_TEMP_DIR/worktrees
branch_prefix=test/
EOF

    run "$PWT_BIN" tree
    [ "$status" -eq 0 ]
}

@test "project command works (loads project module)" {
    run "$PWT_BIN" project list
    [ "$status" -eq 0 ]
}

@test "plugin command works (loads plugin module)" {
    run "$PWT_BIN" plugin list
    [ "$status" -eq 0 ]
}

@test "status stub explains removal" {
    run "$PWT_BIN" status
    [ "$status" -eq 1 ]
    [[ "$output" == *"pwt status was removed"* ]]
}

# ============================================
# Module dependencies
# ============================================

@test "cache functions are available globally" {
    # Cache functions should be in main script, not modules
    run grep "^clear_list_cache()" "$PWT_BIN"
    [ "$status" -eq 0 ]

    run grep "^init_cache_dir()" "$PWT_BIN"
    [ "$status" -eq 0 ]
}
