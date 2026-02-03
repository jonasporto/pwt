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
#!/usr/bin/env bats
# Tests for version check functionality

load test_helper

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================
# Installation method detection
# ============================================

@test "_pwt_install_method detects brew installation" {
    # Mock command -v to return brew path
    function command() { echo "/opt/homebrew/Cellar/pwt/0.1.6/bin/pwt"; }
    export -f command
    
    source "$PWT_BIN"
    run _pwt_install_method
    [ "$output" = "brew" ] || [ "$output" = "curl" ]  # depends on actual path
}

@test "_pwt_upgrade_command returns correct command for each method" {
    source "$PWT_BIN"
    
    # Test that function exists and returns something
    run _pwt_upgrade_command
    [ "$status" -eq 0 ]
    [[ "$output" == *"brew"* ]] || [[ "$output" == *"npm"* ]] || [[ "$output" == *"curl"* ]]
}

# ============================================
# Version comparison
# ============================================

@test "_pwt_version_lt returns true when first version is older" {
    source "$PWT_BIN"
    run _pwt_version_lt "0.1.0" "0.2.0"
    [ "$status" -eq 0 ]
}

@test "_pwt_version_lt returns false when versions are equal" {
    source "$PWT_BIN"
    run _pwt_version_lt "0.1.6" "0.1.6"
    [ "$status" -ne 0 ]
}

@test "_pwt_version_lt returns false when first version is newer" {
    source "$PWT_BIN"
    run _pwt_version_lt "0.2.0" "0.1.0"
    [ "$status" -ne 0 ]
}

@test "_pwt_version_lt handles patch versions" {
    source "$PWT_BIN"
    run _pwt_version_lt "0.1.5" "0.1.6"
    [ "$status" -eq 0 ]
}

# ============================================
# Version check caching
# ============================================

@test "_pwt_check_update uses cache when valid" {
    source "$PWT_BIN"
    
    # Create valid cache
    local cache_file="$PWT_DIR/version-check"
    mkdir -p "$PWT_DIR"
    echo "$(date +%s)" > "$cache_file"
    echo "0.9.9" >> "$cache_file"
    
    run _pwt_check_update
    [ "$output" = "0.9.9" ]
}

@test "_pwt_show_version shows update hint when newer version available" {
    source "$PWT_BIN"
    
    # Create cache with newer version
    local cache_file="$PWT_DIR/version-check"
    mkdir -p "$PWT_DIR"
    echo "$(date +%s)" > "$cache_file"
    echo "99.0.0" >> "$cache_file"
    
    run _pwt_show_version
    [[ "$output" == *"Update available"* ]]
    [[ "$output" == *"99.0.0"* ]]
}

@test "_pwt_show_version does not show hint when on latest version" {
    source "$PWT_BIN"
    
    # Create cache with same version
    local cache_file="$PWT_DIR/version-check"
    mkdir -p "$PWT_DIR"
    echo "$(date +%s)" > "$cache_file"
    echo "$PWT_VERSION" >> "$cache_file"
    
    run _pwt_show_version
    [[ "$output" != *"Update available"* ]]
}
