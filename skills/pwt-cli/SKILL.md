---
name: pwt-cli
description: >
  Drive the pwt CLI (git worktree manager) as an AI agent: machine-readable
  output flags, exit codes, wait primitives instead of poll loops, and the
  standard worktree lifecycle. Use when creating worktrees, starting dev
  servers, running background jobs, or scripting pwt non-interactively.
---

# Driving pwt as an agent

`pwt` manages git worktrees with per-worktree port allocation, background
jobs, and project-defined commands (Pwtfile). This guide covers the flags
and patterns that make it scriptable.

## Machine-readable output

Prefer these over parsing human-oriented output:

```bash
pwt list --porcelain          # JSON list of worktrees
pwt jobs list --porcelain     # JSON list of background jobs
pwt info TICKET-123 --porcelain   # JSON details for one worktree
pwt gateway status --json     # JSON gateway state
pwt current --json            # JSON context for the current worktree
pwt state --json              # versioned snapshot of ALL state (projects, worktrees+meta, jobs)
```

For continuous observation, skip shelling out: `~/.pwt` stores flat
key=value files (`projects/<name>/config`, `state/<project>/<wt>.meta`,
`jobs/<id>.job`) plus an append-only TSV `events.log`
(`ts  project  worktree  kind  detail`). Check `~/.pwt/state-version`
(currently `2`) before parsing — see docs/state-v2-contract.md.

Always pass `--no-input` when running pwt from automation: it closes stdin,
never prompts, and sets `PWT_AGENT=1` for Pwtfile hooks. As a global flag it
must come before the command (`pwt --no-input create ...`); `pwt server` and
Pwtfile commands also accept it after the command.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Usage/argument error |
| 3 | Not found (worktree, project, branch, port, job) |
| 4 | Conflict (already exists, port in use, duplicate job) |
| 5 | Timeout (`jobs wait` / `server wait` exceeded `--timeout`) |
| 6 | Missing dependency (a required external tool is not installed) |

## Wait, don't poll

Never write `sleep`/retry loops around pwt. Use the blocking wait commands;
both poll internally at 0.5s, default `--timeout` is 600s, and exit 5 on
timeout.

Wait for a dev server to accept TCP connections on its allocated port:

```bash
pwt create TICKET-123 && pwt server TICKET-123 --bg && \
    pwt server wait TICKET-123 --timeout 120
```

Wait for a readiness line in the server job's log instead of the port:

```bash
pwt server wait TICKET-123 --log-contains "Listening on" --timeout 120
```

Wait for any background job to finish (accepts a job id or a worktree name;
a worktree name resolves to its running server job, then most recent job).
Any Pwtfile command started with `--bg` prints a JSON job record:

```bash
pwt test TICKET-123 --bg      # Pwtfile command; prints {"job_id":"...", ...}
pwt jobs wait TICKET-123-test-1712345678 --timeout 900
# prints: <job-id> stopped   (exit 0 when the process is gone)
```

`server wait` exits 3 when the worktree has no allocated port or (with
`--log-contains`) no server job exists yet — start one with
`pwt server <wt> --bg` first.

## Worktree lifecycle recipe

```bash
# 1. Create (from a base ref) — runs Pwtfile setup(), allocates a port
pwt --no-input create TICKET-123 --from origin/main

# 2. Start the dev server in the background and wait until it is ready
pwt server TICKET-123 --bg --no-input
pwt server wait TICKET-123 --timeout 120

# 3. Track progress in worktree metadata (free-form keys)
pwt meta set TICKET-123 phase implementing
pwt meta set TICKET-123 next "write tests"
pwt meta set TICKET-123 blocked "waiting on code review"

# 4. Clean up when merged (kills the server on that port, no prompts)
pwt remove TICKET-123 --kill-port -y
```

Other useful commands: `pwt run <wt> <cmd>` (run a command in a worktree),
`pwt logs <wt> [-f]` (background job logs), `pwt jobs` (list jobs),
`pwt jobs stop <id>` / `pwt jobs stop --all`.

## Project-specific commands

Projects define lifecycle hooks and custom commands in a `Pwtfile`
(any function becomes `pwt <function>`). See `pwt help pwtfile` for the
hook contract and the `PWT_*` environment variables available to hooks.
