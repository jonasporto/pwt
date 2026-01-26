#!/usr/bin/env bats
# Tests for pwt version command and flags

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================
# Version flag tests
# ============================================

@test "pwt --version shows version" {
    run "$PWT_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == "pwt version "* ]]
}

@test "pwt -v shows version" {
    run "$PWT_BIN" -v
    [ "$status" -eq 0 ]
    [[ "$output" == "pwt version "* ]]
}

@test "pwt -V shows version" {
    run "$PWT_BIN" -V
    [ "$status" -eq 0 ]
    [[ "$output" == "pwt version "* ]]
}

@test "pwt version command shows version" {
    run "$PWT_BIN" version
    [ "$status" -eq 0 ]
    [[ "$output" == "pwt version "* ]]
}

@test "version output matches expected format (semver)" {
    run "$PWT_BIN" --version
    [ "$status" -eq 0 ]
    # Should match format: pwt version X.Y.Z
    [[ "$output" =~ ^pwt\ version\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "all version variants output the same" {
    local v1 v2 v3 v4
    v1=$("$PWT_BIN" --version)
    v2=$("$PWT_BIN" -v)
    v3=$("$PWT_BIN" -V)
    v4=$("$PWT_BIN" version)

    [ "$v1" = "$v2" ]
    [ "$v2" = "$v3" ]
    [ "$v3" = "$v4" ]
}
