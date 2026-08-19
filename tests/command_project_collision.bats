#!/usr/bin/env bats
# A project may carry the same name as a builtin command ('ports' happened
# for real: the project existed before 0.2.8 turned the word into a
# command). The word resolves to the command, consistently with worktrees
# (0.2.5), and a stderr warning teaches the project's own routes: its
# alias, or --project.

load test_helper

setup() {
    setup_test_env

    # A project literally named after the registry command, with an alias
    mkdir -p "$PWT_DIR/projects/ports" "$TEST_TEMP_DIR/ports-repo" \
        "$PWT_DIR/state/ports" "$TEST_TEMP_DIR/wts/feat"
    cat >"$PWT_DIR/projects/ports/config" <<EOF
name=ports
path=$TEST_TEMP_DIR/ports-repo
worktrees_dir=$TEST_TEMP_DIR/wts
alias=po
EOF
    cat >"$PWT_DIR/state/ports/feat.meta" <<EOF
path=$TEST_TEMP_DIR/wts/feat
branch=feat
port=43911
mode=worktree
EOF

    # A colliding project WITHOUT an alias
    mkdir -p "$PWT_DIR/projects/jobs" "$TEST_TEMP_DIR/jobs-repo"
    cat >"$PWT_DIR/projects/jobs/config" <<EOF
name=jobs
path=$TEST_TEMP_DIR/jobs-repo
worktrees_dir=$TEST_TEMP_DIR/jobs-wts
EOF

    # A normal project: no collision, nothing may change for it
    mkdir -p "$PWT_DIR/projects/app" "$TEST_TEMP_DIR/app-repo"
    cat >"$PWT_DIR/projects/app/config" <<EOF
name=app
path=$TEST_TEMP_DIR/app-repo
worktrees_dir=$TEST_TEMP_DIR/app-wts
EOF
}

teardown() {
    teardown_test_env
}

@test "pwt ports runs the registry even when a project has that name" {
    run "$PWT_BIN" ports
    assert_success
    [[ "$output" == *"43911"* ]] || {
        echo "expected the port registry, got: $output" >&2
        return 1
    }
    [[ "$output" != *"$TEST_TEMP_DIR/ports-repo"* ]] || {
        echo "resolved to the project instead of the command: $output" >&2
        return 1
    }
}

@test "the collision warning lands on stderr and names the project's alias" {
    local err
    err=$("$PWT_BIN" ports 2>&1 >/dev/null)
    [[ "$err" == *"is both"* ]] || {
        echo "expected a collision warning on stderr, got: $err" >&2
        return 1
    }
    [[ "$err" == *"pwt po"* ]] || {
        echo "the warning must offer the project's alias, got: $err" >&2
        return 1
    }
}

@test "json output stays clean: warning on stderr, document on stdout" {
    local out
    out=$("$PWT_BIN" ports --json 2>/dev/null)
    [[ "$out" == "{\"ports\""* ]] || {
        echo "stdout must start with the JSON document, got: $out" >&2
        return 1
    }
    [[ "$out" != *"warning"* ]] || {
        echo "warning leaked into stdout: $out" >&2
        return 1
    }
}

@test "the warning links the docs, and PWT_DOCS_URL relocates the link" {
    local err
    err=$("$PWT_BIN" ports 2>&1 >/dev/null)
    [[ "$err" == *"/docs/commands/#ports"* ]] || {
        echo "expected the docs link, got: $err" >&2
        return 1
    }

    err=$(PWT_DOCS_URL=https://docs.example "$PWT_BIN" ports 2>&1 >/dev/null)
    [[ "$err" == *"https://docs.example/docs/commands/#ports"* ]] || {
        echo "PWT_DOCS_URL must relocate the link, got: $err" >&2
        return 1
    }
}

@test "a colliding project without an alias is told how to create one" {
    local err
    err=$("$PWT_BIN" jobs list 2>&1 >/dev/null || true)
    [[ "$err" == *"pwt project alias jobs"* ]] || {
        echo "expected the alias recipe in the warning, got: $err" >&2
        return 1
    }
}

@test "the wrapper probe declines the colliding name, so the shell will not cd" {
    run "$PWT_BIN" _implicit-cd ports
    assert_failure "the probe must decline: the word belongs to the command"
}

@test "the alias still navigates" {
    run "$PWT_BIN" _implicit-cd po
    assert_success
    [[ "$output" == *"$TEST_TEMP_DIR/ports-repo"* ]] || {
        echo "expected the project path, got: $output" >&2
        return 1
    }
}

@test "bare --project navigates: the probe accepts it and prints the main path" {
    run "$PWT_BIN" _implicit-cd --project ports
    assert_success "the route the warning advertises must actually navigate"
    [[ "$output" == *"$TEST_TEMP_DIR/ports-repo"* ]] || {
        echo "expected the project main path, got: $output" >&2
        return 1
    }

    # With a command after it, the probe declines and the binary runs it
    run "$PWT_BIN" _implicit-cd --project ports list
    assert_failure
}

@test "--project still reaches the colliding project explicitly" {
    run "$PWT_BIN" --project ports list
    assert_success
    [[ "$output" == *"feat"* ]] || {
        echo "expected the project's worktree listing, got: $output" >&2
        return 1
    }
}

# The shell wrapper must not decide on its own: it grew a project
# fast-path that cd'ed before ever consulting the binary's precedence,
# so the binary fix changed nothing in a real terminal. Same class as
# the port-daemon filter: a rule that lives in one code path is a
# coincidence, and the wrapper is a second code path.
@test "the sourced shell function runs the command instead of cd-ing" {
    cd "$TEST_TEMP_DIR"
    # The wrapper's project helper reads ~/.pwt, so the sandbox has to BE
    # ~/.pwt for the fast path to fire at all (which is how this escaped
    # the suite the first time)
    ln -sfn "$PWT_DIR" "$HOME/.pwt"
    run bash -c "
        export PWT_DIR='$PWT_DIR' PWT_NO_UPDATE_CHECK=1
        eval \"\$('$PWT_BIN' shell-init)\"
        pwt ports >\"\$PWT_DIR/wrapper-out\" 2>/dev/null
        echo \"pwd=\$PWD\"
        cat \"\$PWT_DIR/wrapper-out\"
    "
    assert_success
    [[ "$output" == *"pwd=$TEST_TEMP_DIR"* ]] || {
        echo "the wrapper cd'ed away: $output" >&2
        return 1
    }
    [[ "$output" == *"43911"* ]] || {
        echo "expected the registry through the wrapper, got: $output" >&2
        return 1
    }
}

@test "the sourced shell function navigates on bare --project" {
    cd "$TEST_TEMP_DIR"
    ln -sfn "$PWT_DIR" "$HOME/.pwt"
    run bash -c "
        export PWT_DIR='$PWT_DIR' PWT_NO_UPDATE_CHECK=1
        eval \"\$('$PWT_BIN' shell-init)\"
        pwt --project ports >/dev/null 2>&1
        echo \"pwd=\$PWD\"
    "
    assert_success
    [[ "$output" == *"pwd=$TEST_TEMP_DIR/ports-repo"* ]] || {
        echo "the route the warning advertises must cd in a real shell, got: $output" >&2
        return 1
    }
}

@test "the sourced shell function still cds for a non-colliding project" {
    cd "$TEST_TEMP_DIR"
    run bash -c "
        export PWT_DIR='$PWT_DIR' PWT_NO_UPDATE_CHECK=1
        eval \"\$('$PWT_BIN' shell-init)\"
        pwt app >/dev/null 2>&1
        echo \"pwd=\$PWD\"
    "
    assert_success
    [[ "$output" == *"pwd=$TEST_TEMP_DIR/app-repo"* ]] || {
        echo "expected to land in the project main, got: $output" >&2
        return 1
    }
}

@test "a project that collides with nothing keeps resolving as a project" {
    run "$PWT_BIN" _implicit-cd app
    assert_success
    [[ "$output" == *"$TEST_TEMP_DIR/app-repo"* ]]

    local err
    err=$("$PWT_BIN" _implicit-cd app 2>&1 >/dev/null)
    [ -z "$err" ] || {
        echo "no warning may fire without a collision, got: $err" >&2
        return 1
    }
}
