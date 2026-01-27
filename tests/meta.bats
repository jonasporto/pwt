#!/usr/bin/env bats
# Tests for pwt meta command
# Verifies metadata listing, showing, and setting

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
# meta list
# ============================================

@test "pwt meta list shows all worktrees with metadata" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-META1 HEAD
    "$PWT_BIN" create WT-META2 HEAD

    run "$PWT_BIN" meta list
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-META1"* ]]
    [[ "$output" == *"WT-META2"* ]]
}

@test "pwt meta list shows ports in key=value format" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-PORT HEAD

    run "$PWT_BIN" meta list
    [ "$status" -eq 0 ]
    [[ "$output" == *"port="* ]]
}

@test "pwt meta (no args) defaults to list" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-DEFAULT HEAD

    run "$PWT_BIN" meta
    [ "$status" -eq 0 ]
    [[ "$output" == *"WT-DEFAULT"* ]]
}

# ============================================
# meta show
# ============================================

@test "pwt meta show displays worktree metadata as JSON" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-SHOW HEAD

    run "$PWT_BIN" meta show WT-SHOW
    [ "$status" -eq 0 ]
    # Output should contain port
    [[ "$output" == *"port"* ]]
    [[ "$output" == *"path"* ]]
}

@test "pwt meta show outputs valid JSON" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-JSON HEAD

    run "$PWT_BIN" meta show WT-JSON
    [ "$status" -eq 0 ]
    # Extract the JSON part (after "Metadata for WT-JSON:")
    local json_output=$(echo "$output" | tail -n +2)
    echo "$json_output" | jq . > /dev/null 2>&1
    [ "$?" -eq 0 ]
}

@test "pwt meta show fails without worktree name" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-NONAME HEAD

    run "$PWT_BIN" meta show
    [ "$status" -ne 0 ]
    [[ "$output" == *"required"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "pwt meta show shows 'No metadata' for nonexistent worktree" {
    cd "$TEST_REPO"
    run "$PWT_BIN" meta show NONEXISTENT
    [ "$status" -eq 0 ]
    [[ "$output" == *"No metadata"* ]] || [[ "$output" == *"null"* ]]
}

# ============================================
# meta set
# ============================================

@test "pwt meta set updates metadata field" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-SET HEAD

    run "$PWT_BIN" meta set WT-SET description "Test description"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated"* ]] || [[ "$output" == *"✓"* ]]

    # Verify it was set
    run "$PWT_BIN" meta show WT-SET
    [[ "$output" == *"Test description"* ]]
}

@test "pwt meta set requires all arguments" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-ARGS HEAD

    run "$PWT_BIN" meta set WT-ARGS
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "pwt meta set requires value" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-NOVAL HEAD

    run "$PWT_BIN" meta set WT-NOVAL description
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing"* ]] || [[ "$output" == *"Usage"* ]]
}

# ============================================
# meta import
# ============================================

@test "pwt meta import scans existing worktrees" {
    cd "$TEST_REPO"

    # Create worktree
    "$PWT_BIN" create WT-IMPORT HEAD

    run "$PWT_BIN" meta import
    [ "$status" -eq 0 ]
    [[ "$output" == *"Import"* ]] || [[ "$output" == *"worktree"* ]]
}

# ============================================
# meta via project prefix
# ============================================

@test "pwt <project> meta list works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTE HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project meta list
    [ "$status" -eq 0 ]
    # Output should contain worktree name or metadata header
    [[ "$output" == *"WT-REMOTE"* ]] || [[ "$output" == *"Metadata"* ]]
}

@test "pwt <project> meta show works from anywhere" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-REMOTESHOW HEAD

    cd "$TEST_TEMP_DIR"
    run "$PWT_BIN" test-project meta show WT-REMOTESHOW
    [ "$status" -eq 0 ]
    # Check for any metadata field (port or path)
    [[ "$output" == *"port"* ]] || [[ "$output" == *"path"* ]] || [[ "$output" == *"WT-REMOTESHOW"* ]]
}

# ============================================
# Meta column in pwt list
# ============================================

@test "pwt list shows Meta column header" {
    cd "$TEST_REPO"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Meta"* ]]
}

@test "pwt list shows port and description in Meta column" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-METALIST HEAD

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    # Should show port=XXXX and description= in the Meta column
    [[ "$output" == *"port="* ]]
    [[ "$output" == *"description="* ]]
}

@test "pwt list Meta column shows custom metadata fields" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-CUSTOM HEAD

    # Set a custom metadata field
    "$PWT_BIN" meta set WT-CUSTOM env staging
    "$PWT_BIN" meta set WT-CUSTOM description "Test worktree"

    run "$PWT_BIN" list
    [ "$status" -eq 0 ]
    # Should show port in Meta column
    [[ "$output" == *"port="* ]]
    # Should show description
    [[ "$output" == *"description="* ]]

    # Verify env was set via meta show
    run "$PWT_BIN" meta show WT-CUSTOM
    [[ "$output" == *"env"* ]]
    [[ "$output" == *"staging"* ]]
}

# ============================================
# Empty metadata values should not be shown
# ============================================

@test "pwt list Meta column does not show keys with empty values" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-EMPTY HEAD

    # Manually set description to empty string using jq (simulating existing empty metadata)
    local project="test-project"
    jq --arg p "$project" '.[$p]["WT-EMPTY"].description = ""' "$PWT_DIR/meta.json" > "$PWT_DIR/meta.json.tmp"
    mv "$PWT_DIR/meta.json.tmp" "$PWT_DIR/meta.json"

    run "$PWT_BIN" list --refresh
    [ "$status" -eq 0 ]

    # Get the line for WT-EMPTY
    local wt_line=$(echo "$output" | grep "WT-EMPTY")

    # Should show port= but NOT description= (since it's empty)
    [[ "$wt_line" == *"port="* ]]
    # description= should either not appear, or have a fallback value (not empty)
    if [[ "$wt_line" == *"description="* ]]; then
        # If description appears, it should have a non-empty value (fallback)
        [[ "$wt_line" != *"description= "* ]]
        [[ "$wt_line" != *"description=$"* ]]
    fi
}

@test "pwt list Meta column does not show keys with null values" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-NULL HEAD

    # Manually set a null value in metadata using jq
    local project="test-project"
    jq --arg p "$project" '.[$p]["WT-NULL"].customfield = null' "$PWT_DIR/meta.json" > "$PWT_DIR/meta.json.tmp"
    mv "$PWT_DIR/meta.json.tmp" "$PWT_DIR/meta.json"

    run "$PWT_BIN" list --refresh
    [ "$status" -eq 0 ]

    # Get the line for WT-NULL
    local wt_line=$(echo "$output" | grep "WT-NULL")

    # Should NOT show "customfield=" since it's null
    [[ "$wt_line" != *"customfield="* ]]
}

@test "get_extra_metadata excludes empty string values" {
    cd "$TEST_REPO"
    "$PWT_BIN" create WT-GETEXTRA HEAD

    # Set one field with value
    "$PWT_BIN" meta set WT-GETEXTRA env production

    # Manually set empty notes using jq
    local project="test-project"
    jq --arg p "$project" '.[$p]["WT-GETEXTRA"].notes = ""' "$PWT_DIR/meta.json" > "$PWT_DIR/meta.json.tmp"
    mv "$PWT_DIR/meta.json.tmp" "$PWT_DIR/meta.json"

    # Check list output - empty "notes" should not appear
    run "$PWT_BIN" list --refresh
    local wt_line=$(echo "$output" | grep "WT-GETEXTRA")

    # Should show env=production
    [[ "$wt_line" == *"env=production"* ]]
    # Should NOT show notes= (since it's empty)
    [[ "$wt_line" != *"notes="* ]]
}
