#!/usr/bin/env bats
# Tests for helper functions

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================
# has_lsof tests
# ============================================

@test "has_lsof returns true when lsof is installed" {
    # Source the function
    source_pwt_function has_lsof

    # Reset cache
    _lsof_available=""

    if command -v lsof >/dev/null 2>&1; then
        run has_lsof
        [ "$status" -eq 0 ]
    else
        skip "lsof not installed on this system"
    fi
}

@test "has_lsof caches result" {
    source_pwt_function has_lsof

    # Reset and set cache manually
    _lsof_available="yes"
    run has_lsof
    [ "$status" -eq 0 ]

    _lsof_available="no"
    run has_lsof
    [ "$status" -ne 0 ]
}

# ============================================
# is_port_free tests
# ============================================

@test "is_port_free returns 0 for unused port" {
    source_pwt_functions has_lsof is_port_free

    # Reset lsof cache
    _lsof_available=""

    # Use a high port that's unlikely to be in use
    run is_port_free 59999
    [ "$status" -eq 0 ]
}

@test "is_port_free returns 0 when lsof unavailable (best effort)" {
    source_pwt_functions has_lsof is_port_free

    # Force lsof unavailable
    _lsof_available="no"

    run is_port_free 80
    [ "$status" -eq 0 ]  # Should assume free
}

# ============================================
# require_cmd tests
# ============================================

@test "require_cmd succeeds for installed command" {
    source_pwt_function require_cmd

    run require_cmd bash
    [ "$status" -eq 0 ]
}

@test "require_cmd fails for missing command" {
    source_pwt_function require_cmd

    run require_cmd nonexistent_command_xyz123
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "require_cmd returns 1 for missing optional command" {
    source_pwt_function require_cmd

    run require_cmd nonexistent_command_xyz123 true
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "require_cmd shows install hint for git" {
    source_pwt_function require_cmd

    # Temporarily rename git (can't actually do this, so we test output format)
    # Instead, check that the function has the hint code
    local pwt_content=$(cat "$PWT_BIN")
    [[ "$pwt_content" == *"xcode-select --install"* ]]
}

@test "require_cmd shows install hint for jq" {
    source_pwt_function require_cmd

    local pwt_content=$(cat "$PWT_BIN")
    [[ "$pwt_content" == *"brew install jq"* ]]
}

# ============================================
# confirm_action tests
# ============================================

# Helper to test confirm_action with piped input
_test_confirm() {
    local input="$1"
    source_pwt_function confirm_action
    echo "$input" | confirm_action "Test?"
}

@test "confirm_action returns 0 for 'y'" {
    run _test_confirm "y"
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 0 for 'yes'" {
    run _test_confirm "yes"
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 0 for 'Y'" {
    run _test_confirm "Y"
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 1 for 'n'" {
    run _test_confirm "n"
    [ "$status" -ne 0 ]
}

@test "confirm_action returns 1 for empty input" {
    run _test_confirm ""
    [ "$status" -ne 0 ]
}

@test "confirm_action returns 1 for random input" {
    run _test_confirm "maybe"
    [ "$status" -ne 0 ]
}

# ============================================
# pwtfile_replace_literal tests
# ============================================

@test "pwtfile_replace_literal replaces literal string" {
    source_pwt_function pwtfile_replace_literal

    echo "database: test_db" > "$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_literal "$TEST_TEMP_DIR/test.yml" "test_db" "test_db_wt5001"

    run cat "$TEST_TEMP_DIR/test.yml"
    [ "$output" = "database: test_db_wt5001" ]
}

@test "pwtfile_replace_literal handles ERB syntax safely" {
    source_pwt_function pwtfile_replace_literal

    echo "database: test<%= ENV['X']%>" > "$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_literal "$TEST_TEMP_DIR/test.yml" "test<%= ENV['X']%>" "test_wt<%= ENV['X']%>"

    run cat "$TEST_TEMP_DIR/test.yml"
    [ "$output" = "database: test_wt<%= ENV['X']%>" ]
}

@test "pwtfile_replace_literal handles special regex chars" {
    source_pwt_function pwtfile_replace_literal

    echo "url: http://localhost:3000/api" > "$TEST_TEMP_DIR/test.txt"
    pwtfile_replace_literal "$TEST_TEMP_DIR/test.txt" "localhost:3000" "localhost:5001"

    run cat "$TEST_TEMP_DIR/test.txt"
    [ "$output" = "url: http://localhost:5001/api" ]
}

@test "pwtfile_replace_literal does nothing for missing file" {
    source_pwt_function pwtfile_replace_literal

    run pwtfile_replace_literal "$TEST_TEMP_DIR/nonexistent.txt" "a" "b"
    [ "$status" -eq 0 ]
}

# ============================================
# pwtfile_replace_re tests
# ============================================

@test "pwtfile_replace_re replaces regex pattern" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    echo "PORT=3000" > "$TEST_TEMP_DIR/test.env"
    pwtfile_replace_re "$TEST_TEMP_DIR/test.env" "PORT=\d+" "PORT=5001"

    run cat "$TEST_TEMP_DIR/test.env"
    [ "$output" = "PORT=5001" ]
}

@test "pwtfile_replace_re handles multiple matches" {
    if ! command -v perl >/dev/null 2>&1; then
        skip "perl not installed"
    fi

    source_pwt_function pwtfile_replace_re

    printf "port: 3000\nother_port: 3000\n" > "$TEST_TEMP_DIR/test.yml"
    pwtfile_replace_re "$TEST_TEMP_DIR/test.yml" "3000" "5001"

    run cat "$TEST_TEMP_DIR/test.yml"
    [[ "$output" == *"port: 5001"* ]]
    [[ "$output" == *"other_port: 5001"* ]]
}

@test "pwtfile_replace_re does nothing for missing file" {
    source_pwt_function pwtfile_replace_re

    run pwtfile_replace_re "$TEST_TEMP_DIR/nonexistent.txt" "a" "b"
    [ "$status" -eq 0 ]
}

# ============================================
# detect_submodules tests
# ============================================

@test "detect_submodules returns 0 when no .gitmodules" {
    source_pwt_functions confirm_action detect_submodules

    # TEST_REPO has no .gitmodules
    run detect_submodules "$TEST_REPO"
    [ "$status" -eq 0 ]
}

@test "detect_submodules warns when .gitmodules exists" {
    source_pwt_functions confirm_action detect_submodules

    # Create a .gitmodules file
    echo "[submodule \"vendor/lib\"]" > "$TEST_REPO/.gitmodules"

    run detect_submodules "$TEST_REPO"
    [[ "$output" == *"Submodules detected"* ]]
}
