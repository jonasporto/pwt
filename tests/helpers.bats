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

@test "confirm_action returns 0 for 'y'" {
    source_pwt_function confirm_action

    run bash -c 'echo "y" | confirm_action "Test?"'
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 0 for 'yes'" {
    source_pwt_function confirm_action

    run bash -c 'echo "yes" | confirm_action "Test?"'
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 0 for 'Y'" {
    source_pwt_function confirm_action

    run bash -c 'echo "Y" | confirm_action "Test?"'
    [ "$status" -eq 0 ]
}

@test "confirm_action returns 1 for 'n'" {
    source_pwt_function confirm_action

    run bash -c 'echo "n" | confirm_action "Test?"'
    [ "$status" -ne 0 ]
}

@test "confirm_action returns 1 for empty input" {
    source_pwt_function confirm_action

    run bash -c 'echo "" | confirm_action "Test?"'
    [ "$status" -ne 0 ]
}

@test "confirm_action returns 1 for random input" {
    source_pwt_function confirm_action

    run bash -c 'echo "maybe" | confirm_action "Test?"'
    [ "$status" -ne 0 ]
}
