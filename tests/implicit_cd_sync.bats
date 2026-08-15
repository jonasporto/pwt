#!/usr/bin/env bats
# The implicit-cd blocklist in cmd_implicit_cd() must cover every
# user-facing command: a command missing from it can be shadowed by a
# worktree whose name contains the command string (the shell wrapper
# probes `pwt _implicit-cd <arg>` before dispatching). The canonical
# command list is _pwt_commands in completions/pwt.bash, which the
# CLAUDE.md CLI-surface rule keeps up to date.

load test_helper

@test "every completion-listed command is in the implicit-cd blocklist" {
    local blockline
    blockline=$(grep -E '^\s*init \| discover \|' "$PWT_BIN" | head -1)
    [ -n "$blockline" ]

    local commands
    commands=$(sed -n 's/^_pwt_commands="\(.*\)"$/\1/p' "$PWD_DIR/completions/pwt.bash")
    [ -n "$commands" ]

    # Normalize the case pattern into space-separated words for word match
    local normalized=" $(echo "$blockline" | tr '|)' '  ') "
    local missing="" cmd
    for cmd in $commands; do
        if [[ "$normalized" != *" $cmd "* ]]; then
            missing="$missing $cmd"
        fi
    done
    if [ -n "$missing" ]; then
        echo "commands missing from cmd_implicit_cd blocklist:$missing"
        return 1
    fi
}
