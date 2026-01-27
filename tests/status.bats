#!/usr/bin/env bats
# Tests for pwt status command
# Note: Cannot test interactive TUI, focus on help and data collection

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
# status --help
# ============================================

@test "pwt status --help shows usage" {
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pwt status"* ]]
}

@test "pwt status --help shows navigation info" {
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Navigation"* ]]
    [[ "$output" == *"Tab"* ]]
}

@test "pwt status --help shows actions" {
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Actions"* ]]
    [[ "$output" == *"server"* ]]
}

@test "pwt status --help shows views" {
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Views"* ]]
    [[ "$output" == *"Global"* ]]
    [[ "$output" == *"Project"* ]]
    [[ "$output" == *"Worktree"* ]]
}

@test "pwt status --help shows --all flag" {
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all"* ]]
}

@test "pwt status --help shows theme info" {
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Theme"* ]]
    [[ "$output" == *"PWT_THEME"* ]]
}

@test "pwt status -h works same as --help" {
    run "$PWT_BIN" status -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pwt status"* ]]
}

# ============================================
# status command in help
# ============================================

@test "pwt help shows status command" {
    run "$PWT_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
}

@test "status command is listed with description" {
    run "$PWT_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"TUI"* ]] || [[ "$output" == *"dashboard"* ]] || [[ "$output" == *"htop"* ]]
}

# ============================================
# status functions exist (syntax check)
# ============================================

@test "status functions are defined in module" {
    # Check that key functions exist in status module
    run grep -c "^cmd_status()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_collect_data()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_render()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

@test "theme loading function exists" {
    run grep -c "^load_status_theme()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

@test "navigation functions exist" {
    run grep -c "^status_nav_up()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_nav_down()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_nav_back()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

@test "view rendering functions exist" {
    run grep -c "^status_render_pane_worktrees()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_render_pane_projects()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_render_pane_git_status()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

@test "global view functions exist" {
    run grep -c "^status_collect_global_data()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_drill_down_project()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

@test "worktree view functions exist" {
    run grep -c "^status_collect_worktree_data()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_render_pane_commits()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]

    run grep -c "^status_render_pane_stashes()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

# ============================================
# status command dispatch
# ============================================

@test "status command is recognized" {
    # Since we can't run interactive TUI, just verify it's not "unknown command"
    cd "$TEST_REPO"
    run timeout 1 "$PWT_BIN" status --help 2>&1 || true
    [[ "$output" != *"Unknown command"* ]]
}

@test "status --help via project prefix works" {
    # --help should work when specifying project explicitly
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project status --help
    # Should succeed and show usage
    [[ "$output" == *"Usage: pwt status"* ]]
}

# ============================================
# theme variables
# ============================================

@test "theme variables are defined" {
    run grep "^TH_BORDER=" "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]

    run grep "^TH_RESET=" "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]
}

@test "default theme uses ANSI 16 colors" {
    run grep "ANSI 16" "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]
}

# ============================================
# breadcrumb function
# ============================================

@test "breadcrumb function exists" {
    run grep -c "^status_get_breadcrumb()" "$PWT_STATUS_MODULE"
    [ "$output" -ge 1 ]
}

# ============================================
# status state variables
# ============================================

@test "view state variables are defined" {
    run grep 'STATUS_VIEW=' "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]

    run grep 'STATUS_SELECTED_PROJECT=' "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]

    run grep 'STATUS_SELECTED_WORKTREE=' "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]
}

@test "pane state variables are defined" {
    run grep 'STATUS_PANE=' "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]

    run grep 'STATUS_SELECTED=' "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]
}

# ============================================
# status --all from anywhere
# ============================================

@test "pwt status --help works from outside project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pwt status"* ]]
}

@test "pwt status -h works from outside project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" status -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pwt status"* ]]
}

@test "pwt status without --all requires project" {
    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" status
    [ "$status" -ne 0 ]
    [[ "$output" == *"No project detected"* ]]
}

# ============================================
# module loading
# ============================================

@test "status module file exists" {
    [ -f "$PWT_STATUS_MODULE" ]
}

@test "status module has source guard" {
    run grep "_PWT_STATUS_LOADED" "$PWT_STATUS_MODULE"
    [ "$status" -eq 0 ]
}

@test "main script references status module" {
    run grep 'source.*status.sh' "$PWT_BIN"
    [ "$status" -eq 0 ]
}
