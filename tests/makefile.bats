#!/usr/bin/env bats
# Tests for Makefile targets

load test_helper

setup() {
    setup_test_env
    export INSTALL_PREFIX="$TEST_TEMP_DIR/prefix"
}

teardown() {
    teardown_test_env
}

# ============================================
# make install
# ============================================

@test "make install creates bin/pwt" {
    cd "$PWD_DIR"
    make install PREFIX="$INSTALL_PREFIX"
    [ -x "$INSTALL_PREFIX/bin/pwt" ]
}

@test "make install creates lib/pwt modules" {
    cd "$PWD_DIR"
    make install PREFIX="$INSTALL_PREFIX"
    [ -f "$INSTALL_PREFIX/lib/pwt/project.sh" ]
    [ -f "$INSTALL_PREFIX/lib/pwt/list.sh" ]
    [ -f "$INSTALL_PREFIX/lib/pwt/worktree.sh" ]
}

@test "make install creates completions" {
    cd "$PWD_DIR"
    make install PREFIX="$INSTALL_PREFIX"
    [ -f "$INSTALL_PREFIX/share/zsh/site-functions/_pwt" ]
    [ -f "$INSTALL_PREFIX/share/bash-completion/completions/pwt" ]
}

@test "make install creates man page" {
    cd "$PWD_DIR"
    make install PREFIX="$INSTALL_PREFIX"
    [ -f "$INSTALL_PREFIX/share/man/man1/pwt.1" ]
}

# ============================================
# make update
# ============================================

@test "make update detects existing installation" {
    cd "$PWD_DIR"

    # First install
    make install PREFIX="$INSTALL_PREFIX"

    # Update with pwt in PATH
    PATH="$INSTALL_PREFIX/bin:$PATH" make update

    # Should still exist
    [ -x "$INSTALL_PREFIX/bin/pwt" ]
    [ -f "$INSTALL_PREFIX/lib/pwt/project.sh" ]
}

@test "make update updates lib modules" {
    cd "$PWD_DIR"

    # Install
    make install PREFIX="$INSTALL_PREFIX"

    # Modify a module (simulate old version)
    echo "# old version" > "$INSTALL_PREFIX/lib/pwt/project.sh"

    # Update
    PATH="$INSTALL_PREFIX/bin:$PATH" make update

    # Should have new content (not just "# old version")
    [ "$(wc -l < "$INSTALL_PREFIX/lib/pwt/project.sh")" -gt 10 ]
}

@test "make update fails when pwt not in PATH" {
    cd "$PWD_DIR"

    # Don't install, just try update with minimal PATH (need make itself)
    run env PATH="/usr/bin:/bin" make update
    [ "$status" -ne 0 ]
}

@test "make update finds correct prefix even when different from default" {
    cd "$PWD_DIR"

    # Install to custom prefix (simulating ~/.local)
    local custom_prefix="$TEST_TEMP_DIR/custom"
    make install PREFIX="$custom_prefix"

    # Modify module to detect if it gets updated
    echo "# MARKER_OLD_VERSION" >> "$custom_prefix/lib/pwt/project.sh"

    # Run update with pwt in PATH (should find custom prefix, not default /usr/local)
    PATH="$custom_prefix/bin:$PATH" make update

    # Verify it updated the correct location (marker should be gone)
    ! grep -q "MARKER_OLD_VERSION" "$custom_prefix/lib/pwt/project.sh"
}

# ============================================
# make uninstall
# ============================================

@test "make uninstall removes files" {
    cd "$PWD_DIR"

    # Install first
    make install PREFIX="$INSTALL_PREFIX"
    [ -x "$INSTALL_PREFIX/bin/pwt" ]

    # Uninstall
    make uninstall PREFIX="$INSTALL_PREFIX"

    # Should be gone
    [ ! -f "$INSTALL_PREFIX/bin/pwt" ]
    [ ! -d "$INSTALL_PREFIX/lib/pwt" ]
}

# ============================================
# make lint
# ============================================

@test "make lint passes" {
    cd "$PWD_DIR"
    run make lint
    [ "$status" -eq 0 ]
    [[ "$output" == *"All files OK"* ]]
}

# ============================================
# make help
# ============================================

@test "make help shows usage" {
    cd "$PWD_DIR"
    run make help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"update"* ]]
    [[ "$output" == *"uninstall"* ]]
}
