#!/usr/bin/env bats
# Tests for pwt status navigation and key handling

load test_helper

setup() {
    setup_test_env

    # Initialize arrays BEFORE sourcing to avoid unbound variable errors
    # (pwt uses set -u which would fail on empty arrays)
    STATUS_PROJECTS=()
    STATUS_PROJECT_PATHS=()
    STATUS_PROJECT_WT_COUNT=()
    STATUS_PROJECT_DIRTY=()
    STATUS_PROJECT_SERVERS=()
    STATUS_WORKTREES=()
    STATUS_BRANCHES=()
    STATUS_PATHS=()
    STATUS_PORTS=()
    STATUS_ACTIVITY=()
    STATUS_STATUSES=()
    STATUS_AHEAD=()
    STATUS_BEHIND=()

    # Source the main script and status module to get functions
    source "$PWT_BIN"
    source "$PWT_STATUS_MODULE"
}

# Helper to initialize all status variables for tests
# Must be called at the beginning of each test due to bats array scoping
init_status_vars() {
    # Initialize status variables
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=0
    STATUS_PROJECT_SCROLL=0
    STATUS_SELECTED=0
    STATUS_SCROLL=0
    STATUS_SERVER_SELECTED=0
    STATUS_SERVER_SCROLL=0
    STATUS_ACTIVITY_SCROLL=0
    STATUS_SHOW_ALL=true
    STATUS_RUNNING=true
    STATUS_SHOW_HELP=false

    # Mock project data
    STATUS_PROJECTS=("project1" "project2" "project3")
    STATUS_PROJECT_PATHS=("/path1" "/path2" "/path3")
    STATUS_PROJECT_WT_COUNT=(3 2 5)
    STATUS_PROJECT_DIRTY=(1 0 2)
    STATUS_PROJECT_SERVERS=(1 0 0)

    # Mock worktree data
    STATUS_WORKTREES=("@" "wt1" "wt2" "wt3")
    STATUS_BRANCHES=("main" "feature1" "feature2" "feature3")
    STATUS_PATHS=("/main" "/wt1" "/wt2" "/wt3")
    STATUS_PORTS=("3000" "3001" "" "3002")
}

teardown() {
    teardown_test_env
}

# ============================================
# Navigation function tests
# ============================================

@test "status_nav_down increments selection in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=0

    status_nav_down

    [ "$STATUS_PROJECT_SELECTED" -eq 1 ]
}

@test "status_nav_down stops at last item in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=2  # Last item (0-indexed)

    status_nav_down

    [ "$STATUS_PROJECT_SELECTED" -eq 2 ]  # Should not change
}

@test "status_nav_up decrements selection in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=2

    status_nav_up

    [ "$STATUS_PROJECT_SELECTED" -eq 1 ]
}

@test "status_nav_up stops at first item in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=0

    status_nav_up

    [ "$STATUS_PROJECT_SELECTED" -eq 0 ]  # Should not change
}

@test "status_nav_down works in project view" {
    init_status_vars
    STATUS_VIEW="project"
    STATUS_PANE=0
    STATUS_SELECTED=0

    status_nav_down

    [ "$STATUS_SELECTED" -eq 1 ]
}

@test "status_nav_up works in project view" {
    init_status_vars
    STATUS_VIEW="project"
    STATUS_PANE=0
    STATUS_SELECTED=2

    status_nav_up

    [ "$STATUS_SELECTED" -eq 1 ]
}

# ============================================
# Key handling tests
# ============================================

@test "status_handle_key q sets running to false" {
    init_status_vars
    STATUS_RUNNING=true

    status_handle_key "q"

    [ "$STATUS_RUNNING" = false ]
}

@test "status_handle_key Q sets running to false" {
    init_status_vars
    STATUS_RUNNING=true

    status_handle_key "Q"

    [ "$STATUS_RUNNING" = false ]
}

@test "status_handle_key UP calls nav_up" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=1

    status_handle_key "UP"

    [ "$STATUS_PROJECT_SELECTED" -eq 0 ]
}

@test "status_handle_key DOWN calls nav_down" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=0

    status_handle_key "DOWN"

    [ "$STATUS_PROJECT_SELECTED" -eq 1 ]
}

@test "status_handle_key j calls nav_down" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=0

    status_handle_key "j"

    [ "$STATUS_PROJECT_SELECTED" -eq 1 ]
}

@test "status_handle_key k calls nav_up" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PANE=0
    STATUS_PROJECT_SELECTED=1

    status_handle_key "k"

    [ "$STATUS_PROJECT_SELECTED" -eq 0 ]
}

@test "status_handle_key Tab switches pane" {
    init_status_vars
    STATUS_VIEW="project"
    STATUS_PANE=0

    status_handle_key $'\t'

    [ "$STATUS_PANE" -eq 1 ]
}

@test "status_handle_key ? toggles help" {
    init_status_vars
    STATUS_SHOW_HELP=false

    status_handle_key "?"

    [ "$STATUS_SHOW_HELP" = true ]
}

# ============================================
# Drill down tests
# ============================================

@test "drill down from global to project view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PROJECT_SELECTED=0
    STATUS_SELECTED_PROJECT=""

    # Mock load_project_config
    load_project_config() { :; }
    status_collect_data() { :; }
    status_add_activity() { :; }

    status_drill_down_project

    [ "$STATUS_VIEW" = "project" ]
    [ "$STATUS_SELECTED_PROJECT" = "project1" ]
}

@test "drill down from project to worktree view" {
    init_status_vars
    STATUS_VIEW="project"
    STATUS_SELECTED=1
    STATUS_SELECTED_WORKTREE=""

    status_add_activity() { :; }

    status_drill_down_worktree

    [ "$STATUS_VIEW" = "worktree" ]
    [ "$STATUS_SELECTED_WORKTREE" = "wt1" ]
}

@test "nav back from worktree to project" {
    init_status_vars
    STATUS_VIEW="worktree"
    STATUS_SHOW_ALL=true

    status_add_activity() { :; }

    status_nav_back

    [ "$STATUS_VIEW" = "project" ]
}

@test "nav back from project to global" {
    init_status_vars
    STATUS_VIEW="project"
    STATUS_SHOW_ALL=true

    status_collect_global_data() { :; }
    status_add_activity() { :; }

    status_nav_back

    [ "$STATUS_VIEW" = "global" ]
}

# ============================================
# Enter key handling
# ============================================

@test "Enter key (newline) triggers drill down in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PROJECT_SELECTED=0
    STATUS_PANE=0

    # Mock functions
    load_project_config() { :; }
    status_collect_data() { :; }
    status_add_activity() { :; }

    status_handle_key $'\n'

    [ "$STATUS_VIEW" = "project" ]
}

@test "Enter key (carriage return) triggers drill down in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PROJECT_SELECTED=0
    STATUS_PANE=0

    # Mock functions
    load_project_config() { :; }
    status_collect_data() { :; }
    status_add_activity() { :; }

    status_handle_key $'\r'

    [ "$STATUS_VIEW" = "project" ]
}

@test "l key triggers drill down in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PROJECT_SELECTED=0
    STATUS_PANE=0

    # Mock functions
    load_project_config() { :; }
    status_collect_data() { :; }
    status_add_activity() { :; }

    status_handle_key "l"

    [ "$STATUS_VIEW" = "project" ]
}

@test "RIGHT key triggers drill down in global view" {
    init_status_vars
    STATUS_VIEW="global"
    STATUS_PROJECT_SELECTED=0
    STATUS_PANE=0

    # Mock functions
    load_project_config() { :; }
    status_collect_data() { :; }
    status_add_activity() { :; }

    status_handle_key "RIGHT"

    [ "$STATUS_VIEW" = "project" ]
}
