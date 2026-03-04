#!/usr/bin/env bats
# Tests for JSON output escaping

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "pwt current --json escapes description" {
    cd "$TEST_REPO"

    run "$PWT_BIN" init
    [ "$status" -eq 0 ]

    run "$PWT_BIN" create json-test --from HEAD -- 'desc with "quotes" and \ slash'
    [ "$status" -eq 0 ]

    run "$PWT_BIN" use json-test
    [ "$status" -eq 0 ]

    run "$PWT_BIN" current --json
    [ "$status" -eq 0 ]

    local desc
    desc=$(echo "$output" | jq -r '.description')
    [ "$desc" = 'desc with "quotes" and \ slash' ]
}
